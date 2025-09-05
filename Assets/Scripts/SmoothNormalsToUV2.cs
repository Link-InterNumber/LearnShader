using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System.Linq;

public static class SmoothNormalsToUV2
{
    [MenuItem("Tools/Mesh/Write Smooth Normals -> UV2 (Selected)")]
    static void WriteSmoothNormalsForSelection()
    {
        var objs = Selection.gameObjects;
        if (objs == null || objs.Length == 0)
        {
            // also allow mesh assets selected in Project
            var assets = Selection.objects.Where(o => o is Mesh).Cast<Mesh>().ToArray();
            if (assets.Length > 0)
            {
                foreach (var m in assets) ProcessMeshAsset(m);
                AssetDatabase.SaveAssets();
                Debug.Log($"Processed {assets.Length} mesh asset(s).");
                return;
            }

            Debug.LogWarning("No GameObjects or Mesh assets selected.");
            return;
        }

        int processed = 0;
        foreach (var go in objs)
        {
            var mf = go.GetComponent<MeshFilter>();
            if (mf != null && mf.sharedMesh != null)
            {
                ProcessMeshInstance(mf.sharedMesh);
                processed++;
            }
            var smr = go.GetComponent<SkinnedMeshRenderer>();
            if (smr != null && smr.sharedMesh != null)
            {
                ProcessMeshInstance(smr.sharedMesh);
                processed++;
            }
        }
        if (processed > 0)
        {
            AssetDatabase.SaveAssets();
            Debug.Log($"Processed {processed} mesh(es) from selection and wrote smooth normals to UV2.");
        }
        else
        {
            Debug.LogWarning("Selected GameObjects contain no MeshFilter/SkinnedMeshRenderer with a mesh.");
        }
    }

    [MenuItem("Tools/Mesh/Write Smooth Normals -> UV2 (Selected)", true)]
    static bool ValidateWriteSmoothNormalsForSelection()
    {
        return Selection.gameObjects.Length > 0 || Selection.objects.Any(o => o is Mesh);
    }

    static void ProcessMeshAsset(Mesh mesh)
    {
        if (mesh == null) return;
        // If the mesh is an asset, we modify it in place.
        Undo.RecordObject(mesh, "Write Smooth Normals to UV2");
        WriteSmoothNormalsToUV2(mesh);
        EditorUtility.SetDirty(mesh);
    }

    static void ProcessMeshInstance(Mesh mesh)
    {
        if (mesh == null) return;
        // If this is a sharedMesh from a model asset, RecordObject will still register undo for the asset.
        Undo.RecordObject(mesh, "Write Smooth Normals to UV2");
        WriteSmoothNormalsToUV2(mesh);
        EditorUtility.SetDirty(mesh);
    }

    static void WriteSmoothNormalsToUV2(Mesh mesh)
    {
        Vector3[] verts = mesh.vertices;
        int[] tris = mesh.triangles;
        int vcount = verts.Length;

        if (vcount == 0 || tris == null || tris.Length == 0)
            return;

        // 1) group vertex indices by position (quantized to avoid floating precision issues)
        var posToIndices = new Dictionary<Vector3, List<int>>(new Vector3Comparer(1e-5f));
        for (int i = 0; i < vcount; i++)
        {
            Vector3 p = verts[i];
            if (!posToIndices.TryGetValue(p, out var list))
            {
                list = new List<int>();
                posToIndices[p] = list;
            }
            list.Add(i);
        }

        // 2) compute face normals
        int triCount = tris.Length / 3;
        var faceNormals = new Vector3[triCount];
        for (int t = 0; t < triCount; t++)
        {
            int i0 = tris[t * 3 + 0];
            int i1 = tris[t * 3 + 1];
            int i2 = tris[t * 3 + 2];
            Vector3 p0 = verts[i0];
            Vector3 p1 = verts[i1];
            Vector3 p2 = verts[i2];
            Vector3 fn = Vector3.Cross(p1 - p0, p2 - p0);
            if (fn.sqrMagnitude > 1e-12f)
                fn.Normalize();
            else
                fn = Vector3.up;
            faceNormals[t] = fn;
        }

        // 3) collect triangles adjacent to each position-group and sum face normals
        var smoothNormals = new Vector3[vcount];
        // Build a mapping from vertex index to triangle indices for fast lookup
        var vertexToTriangles = new List<int>[vcount];
        for (int i = 0; i < vcount; i++) vertexToTriangles[i] = new List<int>();
        for (int t = 0; t < triCount; t++)
        {
            int i0 = tris[t * 3 + 0];
            int i1 = tris[t * 3 + 1];
            int i2 = tris[t * 3 + 2];
            vertexToTriangles[i0].Add(t);
            vertexToTriangles[i1].Add(t);
            vertexToTriangles[i2].Add(t);
        }

        foreach (var kv in posToIndices)
        {
            var groupIndices = kv.Value;
            // gather unique triangles adjacent to any vertex in this position group
            var triSet = new HashSet<int>();
            foreach (int vi in groupIndices)
            {
                foreach (int t in vertexToTriangles[vi])
                    triSet.Add(t);
            }

            // sum face normals
            Vector3 sum = Vector3.zero;
            foreach (int t in triSet)
                sum += faceNormals[t];

            if (sum.sqrMagnitude < 1e-12f)
                sum = Vector3.up;

            Vector3 smooth = sum.normalized;

            // assign to all vertex indices in this position group
            foreach (int vi in groupIndices)
                smoothNormals[vi] = smooth;
        }

        // 4) write to UV2 (Vector4 list)
        var uv2 = new List<Vector4>(vcount);
        for (int i = 0; i < vcount; i++)
        {
            Vector3 n = smoothNormals[i];
            uv2.Add(new Vector4(n.x, n.y, n.z, 0f));
        }

        mesh.SetUVs(1, uv2);
        // Also update mesh.normals if you want the actual vertex normals replaced:
        // mesh.normals = smoothNormals; // optional

        Debug.Log($"Wrote smooth normals to UV2 for mesh '{mesh.name}'. Vertices: {vcount}, Triangles: {triCount}");
    }

    // Simple comparer that quantizes Vector3 to tolerance for dictionary keying
    class Vector3Comparer : IEqualityComparer<Vector3>
    {
        readonly float eps;
        public Vector3Comparer(float epsilon) { eps = epsilon; }
        public bool Equals(Vector3 a, Vector3 b)
        {
            return Mathf.Abs(a.x - b.x) <= eps && Mathf.Abs(a.y - b.y) <= eps && Mathf.Abs(a.z - b.z) <= eps;
        }
        public int GetHashCode(Vector3 v)
        {
            unchecked
            {
                int hx = Mathf.RoundToInt(v.x / eps);
                int hy = Mathf.RoundToInt(v.y / eps);
                int hz = Mathf.RoundToInt(v.z / eps);
                int hash = 17;
                hash = hash * 31 + hx;
                hash = hash * 31 + hy;
                hash = hash * 31 + hz;
                return hash;
            }
        }
    }
}