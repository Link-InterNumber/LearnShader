using UnityEngine;
using UnityEditor;
using System.IO;
using System.Collections.Generic;
using System.Linq;

public class SmoothNormalMapGenerator : EditorWindow
{
    private Mesh targetMesh;
    private int textureSize = 1024;
    private bool showPreview = true;
    private Texture2D previewTexture;
    private float normalEpsilon = 1e-5f;
    private bool useExistingUV2 = false;

    [MenuItem("Tools/Mesh/Generate Smooth Normal Map")]
    public static void ShowWindow()
    {
        GetWindow<SmoothNormalMapGenerator>("Smooth Normal Map Generator");
    }

    private void OnGUI()
    {
        GUILayout.Label("Smooth Normal Map Generator", EditorStyles.boldLabel);

        EditorGUI.BeginChangeCheck();
        targetMesh = EditorGUILayout.ObjectField("Target Mesh", targetMesh, typeof(Mesh), false) as Mesh;
        textureSize = EditorGUILayout.IntField("Texture Size", textureSize);
        normalEpsilon = EditorGUILayout.FloatField("Normal Precision", normalEpsilon);
        useExistingUV2 = EditorGUILayout.Toggle("Use Existing UV2 If Available", useExistingUV2);
        showPreview = EditorGUILayout.Toggle("Show Preview", showPreview);

        GUI.enabled = targetMesh != null;
        if (GUILayout.Button("Generate Smooth Normal Map"))
        {
            GenerateSmoothNormalMap();
        }
        GUI.enabled = true;

        if (showPreview && previewTexture != null)
        {
            GUILayout.Label("Preview:");
            Rect rect = GUILayoutUtility.GetRect(256, 256);
            EditorGUI.DrawPreviewTexture(rect, previewTexture);
        }
    }

    private void GenerateSmoothNormalMap()
    {
        if (targetMesh == null)
            return;

        // 创建平滑法线图纹理
        Texture2D normalMap = new Texture2D(textureSize, textureSize, TextureFormat.RGBA32, false);

        // 获取或计算平滑法线
        Vector3[] smoothNormals = CalculateSmoothNormals(targetMesh);

        // 使用已有的UV，或者如果没有UV则自动生成
        Vector2[] meshUVs = targetMesh.uv;
        bool hasUVs = meshUVs != null && meshUVs.Length == targetMesh.vertices.Length;

        if (!hasUVs)
        {
            EditorUtility.DisplayProgressBar("Computing Smooth Normals", "No UVs found, generating UV layout...", 0.5f);
            // 简单地生成一个新的网格并自动生成UV
            Unwrapping.GenerateSecondaryUVSet(targetMesh);
            meshUVs = targetMesh.uv2;
        }

        // 将平滑法线值绘制到纹理上
        Color[] pixels = new Color[textureSize * textureSize];
        for (int y = 0; y < textureSize; y++)
        {
            for (int x = 0; x < textureSize; x++)
            {
                // 默认为灰色 (0.5, 0.5, 1) - 代表向上的法线
                pixels[y * textureSize + x] = new Color(0.5f, 0.5f, 1f, 1f);
            }
        }

        EditorUtility.DisplayProgressBar("Computing Smooth Normals", "Baking normals to texture...", 0.7f);

        // 对每个三角形，将平滑法线烘焙到纹理
        int[] triangles = targetMesh.triangles;
        for (int i = 0; i < triangles.Length; i += 3)
        {
            int v1 = triangles[i];
            int v2 = triangles[i + 1];
            int v3 = triangles[i + 2];

            Vector2 uv1 = meshUVs[v1];
            Vector2 uv2 = meshUVs[v2];
            Vector2 uv3 = meshUVs[v3];

            Vector3 normal1 = smoothNormals[v1];
            Vector3 normal2 = smoothNormals[v2];
            Vector3 normal3 = smoothNormals[v3];

            // 将法线转换为颜色 (将 -1,1 范围映射到 0,1 范围)
            Color c1 = NormalToColor(normal1);
            Color c2 = NormalToColor(normal2);
            Color c3 = NormalToColor(normal3);

            RasterizeTriangle(pixels, textureSize, textureSize,
                              uv1, uv2, uv3,
                              c1, c2, c3);
        }

        normalMap.SetPixels(pixels);
        normalMap.Apply();

        // 保存纹理到文件
        string meshPath = AssetDatabase.GetAssetPath(targetMesh);
        string directory = Path.GetDirectoryName(meshPath);
        string fileName = Path.GetFileNameWithoutExtension(meshPath) + "_SmoothNormals.png";
        string savePath = Path.Combine(directory, fileName);

        byte[] pngData = normalMap.EncodeToPNG();
        File.WriteAllBytes(savePath, pngData);
        AssetDatabase.Refresh();

        // 设置正确的纹理类型为法线贴图
        TextureImporter importer = AssetImporter.GetAtPath(savePath) as TextureImporter;
        if (importer != null)
        {
            importer.textureType = TextureImporterType.NormalMap;
            importer.SaveAndReimport();
        }

        // 更新预览
        previewTexture = normalMap;

        EditorUtility.ClearProgressBar();
        Debug.Log($"平滑法线图已保存到: {savePath}");
    }

    private Vector3[] CalculateSmoothNormals(Mesh mesh)
    {
        // 首先检查是否已经有存储在UV2中的平滑法线
        if (useExistingUV2)
        {
            List<Vector4> existingUV2 = new List<Vector4>();
            mesh.GetUVs(1, existingUV2);
            if (existingUV2.Count == mesh.vertexCount)
            {
                Debug.Log("Using existing smooth normals from UV2 channel.");
                Vector3[] normals = new Vector3[existingUV2.Count];
                for (int i = 0; i < existingUV2.Count; i++)
                {
                    Vector4 uv2 = existingUV2[i];
                    normals[i] = new Vector3(uv2.x, uv2.y, uv2.z).normalized;
                }
                return normals;
            }
        }

        // 否则，计算平滑法线
        EditorUtility.DisplayProgressBar("Computing Smooth Normals", "Calculating smooth normal values...", 0.0f);

        Vector3[] vertices = mesh.vertices;
        int[] triangles = mesh.triangles;
        int vcount = vertices.Length;

        if (vcount == 0 || triangles == null || triangles.Length == 0)
            return mesh.normals; // 如果没有顶点数据，则返回默认法线

        // 1) 按位置分组顶点索引（量化以避免浮点精度问题）
        var posToIndices = new Dictionary<Vector3, List<int>>(new Vector3Comparer(normalEpsilon));
        for (int i = 0; i < vcount; i++)
        {
            Vector3 p = vertices[i];
            if (!posToIndices.TryGetValue(p, out var list))
            {
                list = new List<int>();
                posToIndices[p] = list;
            }
            list.Add(i);

            if (i % 1000 == 0)
                EditorUtility.DisplayProgressBar("Computing Smooth Normals", "Grouping vertices...", (float)i / vcount);
        }

        // 2) 计算面法线
        int triCount = triangles.Length / 3;
        var faceNormals = new Vector3[triCount];
        for (int t = 0; t < triCount; t++)
        {
            int i0 = triangles[t * 3 + 0];
            int i1 = triangles[t * 3 + 1];
            int i2 = triangles[t * 3 + 2];
            Vector3 p0 = vertices[i0];
            Vector3 p1 = vertices[i1];
            Vector3 p2 = vertices[i2];
            Vector3 fn = Vector3.Cross(p1 - p0, p2 - p0);
            if (fn.sqrMagnitude > 1e-12f)
                fn.Normalize();
            else
                fn = Vector3.up;
            faceNormals[t] = fn;

            if (t % 1000 == 0)
                EditorUtility.DisplayProgressBar("Computing Smooth Normals", "Calculating face normals...", (float)t / triCount);
        }

        // 3) 收集与每个位置组相邻的三角形并求和面法线
        var smoothNormals = new Vector3[vcount];
        // 构建从顶点索引到三角形索引的映射，以便快速查找
        var vertexToTriangles = new List<int>[vcount];
        for (int i = 0; i < vcount; i++) vertexToTriangles[i] = new List<int>();
        for (int t = 0; t < triCount; t++)
        {
            int i0 = triangles[t * 3 + 0];
            int i1 = triangles[t * 3 + 1];
            int i2 = triangles[t * 3 + 2];
            vertexToTriangles[i0].Add(t);
            vertexToTriangles[i1].Add(t);
            vertexToTriangles[i2].Add(t);
        }

        int groupCount = 0;
        int totalGroups = posToIndices.Count;
        foreach (var kv in posToIndices)
        {
            var groupIndices = kv.Value;
            // 收集与此位置组中任何顶点相邻的唯一三角形
            var triSet = new HashSet<int>();
            foreach (int vi in groupIndices)
            {
                foreach (int t in vertexToTriangles[vi])
                    triSet.Add(t);
            }

            // 对面法线求和
            Vector3 sum = Vector3.zero;
            foreach (int t in triSet)
                sum += faceNormals[t];

            if (sum.sqrMagnitude < 1e-12f)
                sum = Vector3.up;

            Vector3 smooth = sum.normalized;

            // 将结果分配给此位置组中的所有顶点索引
            foreach (int vi in groupIndices)
                smoothNormals[vi] = smooth;

            if (groupCount % 1000 == 0 || groupCount == totalGroups - 1)
                EditorUtility.DisplayProgressBar("Computing Smooth Normals", "Processing vertex groups...", (float)groupCount / totalGroups);
            
            groupCount++;
        }

        return smoothNormals;
    }

    private Color NormalToColor(Vector3 normal)
    {
        // 将法线从 [-1,1] 范围映射到 [0,1] 范围，用于存储在纹理中
        return new Color(
            normal.x * 0.5f + 0.5f,
            normal.y * 0.5f + 0.5f,
            normal.z * 0.5f + 0.5f,
            1.0f
        );
    }

    private void RasterizeTriangle(Color[] pixels, int width, int height,
                                  Vector2 uv1, Vector2 uv2, Vector2 uv3,
                                  Color c1, Color c2, Color c3)
    {
        // 将UV坐标转换为像素坐标
        Vector2 p1 = new Vector2(uv1.x * width, uv1.y * height);
        Vector2 p2 = new Vector2(uv2.x * width, uv2.y * height);
        Vector2 p3 = new Vector2(uv3.x * width, uv3.y * height);

        // 计算三角形的包围盒
        int minX = Mathf.FloorToInt(Mathf.Min(p1.x, Mathf.Min(p2.x, p3.x)));
        int maxX = Mathf.CeilToInt(Mathf.Max(p1.x, Mathf.Max(p2.x, p3.x)));
        int minY = Mathf.FloorToInt(Mathf.Min(p1.y, Mathf.Min(p2.y, p3.y)));
        int maxY = Mathf.CeilToInt(Mathf.Max(p1.y, Mathf.Max(p2.y, p3.y)));

        // 限制在纹理范围内
        minX = Mathf.Max(0, minX);
        maxX = Mathf.Min(width - 1, maxX);
        minY = Mathf.Max(0, minY);
        maxY = Mathf.Min(height - 1, maxY);

        // 三角形光栅化
        for (int y = minY; y <= maxY; y++)
        {
            for (int x = minX; x <= maxX; x++)
            {
                Vector2 pixelPos = new Vector2(x + 0.5f, y + 0.5f);

                // 计算重心坐标
                Vector3 barycentric = ComputeBarycentric(pixelPos, p1, p2, p3);

                if (barycentric.x >= 0 && barycentric.y >= 0 && barycentric.z >= 0)
                {
                    // 使用重心坐标插值颜色
                    Color color = barycentric.x * c1 + barycentric.y * c2 + barycentric.z * c3;

                    // 写入像素
                    int pixelIndex = y * width + x;
                    pixels[pixelIndex] = color;
                }
            }
        }
    }

    private Vector3 ComputeBarycentric(Vector2 point, Vector2 a, Vector2 b, Vector2 c)
    {
        Vector2 v0 = b - a;
        Vector2 v1 = c - a;
        Vector2 v2 = point - a;

        float d00 = Vector2.Dot(v0, v0);
        float d01 = Vector2.Dot(v0, v1);
        float d11 = Vector2.Dot(v1, v1);
        float d20 = Vector2.Dot(v2, v0);
        float d21 = Vector2.Dot(v2, v1);

        float denom = d00 * d11 - d01 * d01;

        if (Mathf.Abs(denom) < 0.0000001f)
            return new Vector3(-1, -1, -1);

        float v = (d11 * d20 - d01 * d21) / denom;
        float w = (d00 * d21 - d01 * d20) / denom;
        float u = 1.0f - v - w;

        return new Vector3(u, v, w);
    }

    // 用于Vector3比较的辅助类
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