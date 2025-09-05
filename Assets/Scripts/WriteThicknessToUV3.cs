using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System.Linq;

public static class WriteThicknessToUV3
{
    const float kEpsilon = 1e-4f;
    const float kMaxDistance = 1e6f;

    [MenuItem("Tools/Mesh/Write Thickness -> UV3 (Selected)")]
    static void MenuWriteThicknessForSelection()
    {
        var objs = Selection.gameObjects;
        var meshAssets = Selection.objects.Where(o => o is Mesh).Cast<Mesh>().ToArray();

        int processed = 0;
        if (objs != null && objs.Length > 0)
        {
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
        }

        if (meshAssets.Length > 0)
        {
            foreach (var m in meshAssets) ProcessMeshAsset(m);
            processed += meshAssets.Length;
        }

        if (processed > 0)
        {
            AssetDatabase.SaveAssets();
            Debug.Log($"Processed {processed} mesh(es) and wrote thickness to UV3.");
        }
        else
        {
            Debug.LogWarning("No Mesh assets or GameObjects with meshes selected.");
        }
    }

    [MenuItem("Tools/Mesh/Write Thickness -> UV3 (Selected)", true)]
    static bool ValidateMenuWriteThicknessForSelection()
    {
        return Selection.gameObjects.Length > 0 || Selection.objects.Any(o => o is Mesh);
    }

    static void ProcessMeshAsset(Mesh mesh)
    {
        if (mesh == null) return;
        Undo.RecordObject(mesh, "Write Thickness to UV3");
        WriteThicknessToUV3(mesh);
        EditorUtility.SetDirty(mesh);
    }

    static void ProcessMeshInstance(Mesh mesh)
    {
        if (mesh == null) return;
        Undo.RecordObject(mesh, "Write Thickness to UV3");
        WriteThicknessToUV3(mesh);
        EditorUtility.SetDirty(mesh);
    }

    static void WriteThicknessToUV3(Mesh mesh)
    {
        Vector3[] verts = mesh.vertices;
        Vector3[] normals = mesh.normals;
        int[] tris = mesh.triangles;
        int vcount = verts.Length;
        if (vcount == 0 || tris == null || tris.Length == 0)
            return;

        // Build vertex->triangle adjacency
        int triCount = tris.Length / 3;
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

        // Prepare triangles in object space for intersection
        var triA = new Vector3[triCount];
        var triB = new Vector3[triCount];
        var triC = new Vector3[triCount];
        for (int t = 0; t < triCount; t++)
        {
            triA[t] = verts[tris[t * 3 + 0]];
            triB[t] = verts[tris[t * 3 + 1]];
            triC[t] = verts[tris[t * 3 + 2]];
        }

        var uv3 = new List<Vector4>(vcount);

        // Optionally show progress bar
        try
        {
            for (int vi = 0; vi < vcount; vi++)
            {
                if (EditorUtility.DisplayCancelableProgressBar("Writing Thickness -> UV3", $"Vertex {vi+1}/{vcount}", (float)vi / vcount))
                    break;

                Vector3 p = verts[vi];
                Vector3 n = (normals != null && normals.Length == vcount) ? normals[vi] : EstimateVertexNormal(vertexToTriangles[vi], triA, triB, triC);

                if (n.sqrMagnitude < 1e-8f) n = Vector3.up;
                n.Normalize();

                // Exclude triangles adjacent to this vertex (to avoid immediate self-intersection)
                var excludeTris = new HashSet<int>(vertexToTriangles[vi]);

                // Cast forward
                float forwardDist = RaycastTriangles(p + n * kEpsilon, n, triA, triB, triC, excludeTris);
                // Cast backward
                float backwardDist = RaycastTriangles(p - n * kEpsilon, -n, triA, triB, triC, excludeTris);

                float thickness = 0f;
                bool fHit = forwardDist < kMaxDistance;
                bool bHit = backwardDist < kMaxDistance;
                if (fHit && bHit)
                {
                    thickness = forwardDist + backwardDist;
                }
                else if (fHit)
                {
                    thickness = forwardDist;
                }
                else if (bHit)
                {
                    thickness = backwardDist;
                }
                else
                {
                    thickness = 0f; // no intersection found, likely open mesh
                }

                // Store thickness into uv3.xyz (same value in xyz)
                uv3.Add(new Vector4(thickness, thickness, thickness, 0f));
            }
        }
        finally
        {
            EditorUtility.ClearProgressBar();
        }

        mesh.SetUVs(2, uv3);
        Debug.Log($"Wrote thickness to UV3 for mesh '{mesh.name}'. Vertices: {vcount}, Triangles: {triCount}");
    }

    // Raycast all triangles, return nearest positive distance, or kMaxDistance if none
    static float RaycastTriangles(Vector3 origin, Vector3 dir, Vector3[] a, Vector3[] b, Vector3[] c, HashSet<int> excludeTris)
    {
        float nearest = kMaxDistance;
        int triCount = a.Length;
        for (int t = 0; t < triCount; t++)
        {
            if (excludeTris != null && excludeTris.Contains(t)) continue;

            if (RayTriangleIntersect(origin, dir, a[t], b[t], c[t], out float dist))
            {
                if (dist > 0f && dist < nearest)
                    nearest = dist;
            }
        }
        return nearest;
    }

    // Moller-Trumbore ray-triangle intersection in object space.
    // Returns true and distance t if hit.
    static bool RayTriangleIntersect(Vector3 origin, Vector3 dir, Vector3 v0, Vector3 v1, Vector3 v2, out float t)
    {
        t = 0f;
        Vector3 edge1 = v1 - v0;
        Vector3 edge2 = v2 - v0;
        Vector3 pvec = Vector3.Cross(dir, edge2);
        float det = Vector3.Dot(edge1, pvec);
        if (Mathf.Abs(det) < 1e-8f) return false;
        float invDet = 1.0f / det;
        Vector3 tvec = origin - v0;
        float u = Vector3.Dot(tvec, pvec) * invDet;
        if (u < 0f || u > 1f) return false;
        Vector3 qvec = Vector3.Cross(tvec, edge1);
        float v = Vector3.Dot(dir, qvec) * invDet;
        if (v < 0f || u + v > 1f) return false;
        t = Vector3.Dot(edge2, qvec) * invDet;
        if (t <= 1e-6f) return false;
        return true;
    }

    // Fallback simple normal estimation if mesh.normals missing: average adjacent face normals.
    static Vector3 EstimateVertexNormal(List<int> adjacentTris, Vector3[] a, Vector3[] b, Vector3[] c)
    {
        Vector3 sum = Vector3.zero;
        foreach (int t in adjacentTris)
        {
            Vector3 fn = Vector3.Cross(b[t] - a[t], c[t] - a[t]);
            if (fn.sqrMagnitude > 1e-12f) sum += fn.normalized;
        }
        if (sum.sqrMagnitude < 1e-12f) return Vector3.up;
        return sum.normalized;
    }
}