using UnityEngine;
using System.Collections;
using System.Collections.Generic;
using UnityEngine.UI;
using UnityEngine.EventSystems;
using UnityEngine.XR;
using UnityEngine.XR.Interaction.Toolkit;
using UnityEngine.SceneManagement;
using Unity.Mathematics;
using System;
using System.IO;
using System.Globalization;
using System.Linq;
using UnityEngine.XR.Interaction.Toolkit.UI;
using Unity.Profiling;
using System.Threading.Tasks;
using TMPro;
using DataUtils.FloodDataUtils;
using CesiumForUnity;

public class FloodVisualizer : MonoBehaviour
{
    [SerializeField]
    private GameObject subMeshTemplate;

    [SerializeField]
    private GameObject debugCube;

    private CesiumGeoreference georeference;

    private Cesium3DTileset terrainTileset;

    private FloodDataLoader dataLoader;
    private int numFolders;

    private int height;
    private int width;

    private double2[,] ecefMatrix;
    private double2[,] wgs84Matrix;
    private double2[,] srcCrsMatrix;
    private double[,] waterDepthMatrix;
    private bool[,] invalidMask;
    private double[,] terrainHeightMatrix;
    private double minWaterDepth;
    private double maxWaterDepth;
    private double minTerrainHeight;
    private double maxTerrainHeight;
    public bool isMeshReady = false;
    private int subMeshPatchSize = 16;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    async void Start()
    {
        dataLoader = gameObject.GetComponent<FloodDataLoader>();
        // Find the sibling GameObject named "Cesium World Terrain"
        Transform parent = transform.parent;
        Transform cesiumTransform = parent.Find("Cesium World Terrain");

        terrainTileset = cesiumTransform.GetComponent<Cesium3DTileset>();
        georeference = GetComponentInParent<CesiumGeoreference>();

        if (dataLoader != null)
        {
            if (dataLoader.isDataReady[0])
            {
                ParseLoadedFloodData(dataLoader.data[0]);
                VisualizeFloodData(dataLoader.data[0]);
            }
            else
            {
                dataLoader.DataLoaded += ParseLoadedFloodData;
                dataLoader.DataLoaded += VisualizeFloodData;
            }
        }
    }

    // Update is called once per frame
    void Update()
    {

    }

    void ParseLoadedFloodData(FloodSimulationData data)
    {
        height = data.height;
        width = data.width;
        ecefMatrix = data.ecefMatrix;
        wgs84Matrix = data.wgs84Matrix;
        srcCrsMatrix = data.srcCrsMatrix;
        waterDepthMatrix = data.waterDepthMatrix;
        invalidMask = data.invalidMask;
    }

    async void VisualizeFloodData(FloodSimulationData data)
    {
        terrainHeightMatrix = new double[height, width];
        await GetTerrainHeights();
        await GetTerrainHeightRange();
        await AddNoiseToWaterDepth();
        await GetWaterDepthRange();
        await GenerateWaterMesh();
        isMeshReady = true;
    }

    async Task AddNoiseToWaterDepth()
    {
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                waterDepthMatrix[y, x] = 0.5;
                // waterDepthMatrix[y, x] = waterDepthMatrix[y, x] * 10f;
                waterDepthMatrix[y, x] = waterDepthMatrix[y, x] + (double)(Math.Clamp(Mathf.PerlinNoise((float)(width - x) / (float)width, (float)y / (float)height), 0f, 1f) * 3f);
                // waterDepthMatrix[y, x] = 5.0;

                /***
                if (y < 128 && x < 128) { waterDepthMatrix[y, x] = 0.2; }
                if (y < 128 && x >= 128) { waterDepthMatrix[y, x] = 5.0; }
                if (y >= 128 && x < 128) { waterDepthMatrix[y, x] = 10.0; }
                if (y >= 128 && x >= 128) { waterDepthMatrix[y, x] =30.0; }
                ***/

            }
        }
    }
    async Task GetWaterDepthRange()
    {
        minWaterDepth = double.MaxValue;
        maxWaterDepth = double.MinValue;
        int count = 0;

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                if (invalidMask[y, x]) { continue; }
                minWaterDepth = Math.Min(minWaterDepth, waterDepthMatrix[y, x]);
                maxWaterDepth = Math.Max(maxWaterDepth, waterDepthMatrix[y, x]);

                count++;

                if (count % 10000 == 0)
                {
                    await Task.Yield();
                }
            }
        }
    }

    async Task GetTerrainHeightRange()
    {
        minTerrainHeight = double.MaxValue;
        maxTerrainHeight = double.MinValue;
        int count = 0;

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                if (invalidMask[y, x]) { continue; }
                minTerrainHeight = Math.Min(minTerrainHeight, terrainHeightMatrix[y, x]);
                maxTerrainHeight = Math.Max(maxTerrainHeight, terrainHeightMatrix[y, x]);

                count++;

                if (count % 10000 == 0)
                {
                    await Task.Yield();
                }
            }
        }
    }

    async Task GetTerrainHeights()
    {
        int count = 0;
        int countLimit = 10000;

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                if (invalidMask[y, x]) continue;
                double2 lonLat = wgs84Matrix[y, x];
                double3 queryPoint = new double3(lonLat.x, lonLat.y, 0);

                // Query terrain height for this point
                var result = await terrainTileset.SampleHeightMostDetailed(new double3[] { queryPoint });

                // Check the return status
                if (result == null || result.longitudeLatitudeHeightPositions == null || result.longitudeLatitudeHeightPositions.Length < 1)
                {
                    Debug.LogWarning($"Failed to sample height at ({queryPoint.x}, {queryPoint.y})");
                }

                // Populate the terrainHeightMatrix 
                double3 wgs3D = result.longitudeLatitudeHeightPositions[0];
                terrainHeightMatrix[y, x] = wgs3D.z;

                count++;

                // Let Unity breathe every countLimit steps
                if (count % countLimit == 0)
                {
                    await Task.Yield(); // Releases control back to Unity's main thread just like `yield return null`
                }
            }
        }
    }

    async Task GenerateWaterMesh()
    {
        int count = 0;
        int countPatchLimit = 10;

        for (int py = 0; py < subMeshPatchSize; py++)
        {
            for (int px = 0; px < subMeshPatchSize; px++)
            {
                if (count < 256)
                {
                    int sizeX = width / subMeshPatchSize - 1;
                    int sizeY = height / subMeshPatchSize - 1;
                    int xOffset = 0;
                    int yOffset = 0;

                    if (py > 0) { sizeY++; }
                    if (px > 0) { sizeX++; }
                    if (py > 0) { yOffset--; }
                    if (px > 0) { xOffset--; }

                    int vertCountPerSide = (sizeX + 1) * (sizeY + 1);
                    int totalVerts = vertCountPerSide * 2;
                    
                    // Create a Submesh 
                    string subMeshObjectName = "SubMeshContainer_" + count.ToString("D6");
                    GameObject subMeshContainer = new GameObject(subMeshObjectName);
                    subMeshContainer.transform.SetParent(transform, false);

                    // Anchor the SubMeshx
                    subMeshContainer.AddComponent<CesiumGlobeAnchor>();
                    CesiumGlobeAnchor anchor = subMeshContainer.GetComponent<CesiumGlobeAnchor>();

                    int centerX = px * subMeshPatchSize + subMeshPatchSize / 2;
                    int centerY = py * subMeshPatchSize + subMeshPatchSize / 2;

                    if (centerX < width && centerY < height)
                    {
                        double2 centerLonLat = wgs84Matrix[centerY, centerX];
                        double centerTerrainHeight = terrainHeightMatrix[centerY, centerX];
                        anchor.longitudeLatitudeHeight = new double3(centerLonLat.x, centerLonLat.y, 0.0);
                    }


                    Debug.Log($"Center X: {centerX}, Center Y: {centerY}");
                    Debug.Log($"SubMesh anchor position (WGS84): {anchor.longitudeLatitudeHeight}");
                    Debug.Log($"SubMesh anchor position (ECEF): {anchor.positionGlobeFixed}");

                    // Create the mesh
                    GameObject subMesh = Instantiate(subMeshTemplate);
                    subMesh.transform.SetParent(subMeshContainer.transform, false);
                    subMesh.SetActive(true);

                    // CesiumGlobeAnchor anchorSubMesh = subMesh.GetComponent<CesiumGlobeAnchor>();
                    // anchorSubMesh.positionGlobeFixed = anchor.positionGlobeFixed;

                    Vector3[] vertices = new Vector3[totalVerts];
                    Color[] colors = new Color[totalVerts];

                    List<int> triangles = new List<int>();

                    double3 anchorPos = anchor.positionGlobeFixed;
                    double3 anchorLonLatHeight = CesiumWgs84Ellipsoid.EarthCenteredEarthFixedToLongitudeLatitudeHeight(anchorPos);
                    float3 anchorPosUnity = (float3)georeference.TransformEarthCenteredEarthFixedPositionToUnity(anchorPos);

                    Debug.Log($"SubMesh anchor position (Unity): {anchorPosUnity}");

                    int yMin = py * subMeshPatchSize + yOffset;
                    int xMin = px * subMeshPatchSize + xOffset;

                    Debug.Log($"py: {py}, px: {px}, yMin: {yMin}, xMin: {xMin}");


                    // Add vertices
                    // Create top and bottom vertices
                    for (int y = 0; y <= sizeY; y++)
                    {
                        for (int x = 0; x <= sizeX; x++)
                        {
                            int i = y * (sizeX + 1) + x;
                            double2 vertexLonLat = wgs84Matrix[yMin + y, xMin + x];
                            double vertexWaterHeight = waterDepthMatrix[yMin + y, xMin + x];
                            double vertexBottomHeight = terrainHeightMatrix[yMin + y, xMin + x] + 0.1;
                            double vertexTopHeight = vertexBottomHeight + vertexWaterHeight;

                            double3 vertexTopLonLatHeight = new double3(vertexLonLat.x, vertexLonLat.y, vertexTopHeight);
                            double3 vertexBottomLonLatHeight = new double3(vertexLonLat.x, vertexLonLat.y, vertexBottomHeight);

                            double3 vertexTopPos = CesiumWgs84Ellipsoid.LongitudeLatitudeHeightToEarthCenteredEarthFixed(vertexTopLonLatHeight);
                            double3 vertexBottomPos = CesiumWgs84Ellipsoid.LongitudeLatitudeHeightToEarthCenteredEarthFixed(vertexBottomLonLatHeight);
                            float3 vertexTopPosUnity = (float3)georeference.TransformEarthCenteredEarthFixedPositionToUnity(vertexTopPos);
                            float3 vertexBottomPosUnity = (float3)georeference.TransformEarthCenteredEarthFixedPositionToUnity(vertexBottomPos);

                            vertices[i] = vertexTopPosUnity - anchorPosUnity; // top
                            vertices[i + vertCountPerSide] = vertexBottomPosUnity - anchorPosUnity; // bottom

                            float normalized = Mathf.InverseLerp((float)minWaterDepth, (float)maxWaterDepth, (float)vertexWaterHeight);

                            Color dynamicColor = Color.Lerp(new Color(0.1f, 0.2f, 1f), Color.cyan, normalized);
                            float dynamicAlpha = Mathf.Lerp(0.1f, 0.8f, Mathf.InverseLerp(0f, 2f, (float)vertexWaterHeight));
                            colors[i + vertCountPerSide] = new Color(dynamicColor.r, dynamicColor.g, dynamicColor.b, 0.1f);
                            // colors[i] = new Color(0.05f, 0.1f, 0.3f, 0.7f);
                            colors[i] = new Color(dynamicColor.r, dynamicColor.g, dynamicColor.b, 0.7f);

                        }
                    }

                    // Build top surface triangles (clockwise from above)
                    // AddLevelFace(triangles, sizeY, sizeX, yMin, xMin, 0);
                    AddLevelFace(triangles, sizeY, sizeX, yMin, xMin, 0, false);

                    // Build bottom surface triangles (clockwise from above)
                    AddLevelFace(triangles, sizeY, sizeX, yMin, xMin, vertCountPerSide, true);

                    // Build the side faces
                    AddSideFaces(triangles, py, px, sizeY, sizeX, yMin, xMin, vertCountPerSide);

                    // Build the interior faces
                    AddInteriorFaces(triangles, sizeY, sizeX, yMin, xMin, vertCountPerSide);

                    Debug.Log($"Min Water Depth: {minWaterDepth}, Max Water Depth: {maxWaterDepth}");


                    Mesh mesh = new Mesh();
                    mesh.vertices = vertices;
                    mesh.triangles = triangles.ToArray();
                    mesh.colors = colors;
                    mesh.RecalculateNormals();
                    subMesh.GetComponent<MeshFilter>().mesh = mesh;
                }

                count++;

                if (count % countPatchLimit == 0)
                {
                    await Task.Yield();
                }
            }
        }

        async void AddLevelFace(List<int> triangles, int sizeY, int sizeX, int yMin, int xMin, int offset, bool clockwise=true)
        {
            for (int y = 0; y < sizeY; y++)
            {
                for (int x = 0; x < sizeX; x++)
                {
                    int ly = yMin + y;
                    int lx = xMin + x;

                    if (invalidMask[ly, lx] || invalidMask[ly + 1, lx] || invalidMask[ly, lx + 1] || invalidMask[ly + 1, lx + 1])
                        continue;

                    int i0 = y * (sizeX + 1) + x + offset;
                    int i1 = i0 + 1;
                    int i2 = i0 + (sizeX + 1);
                    int i3 = i2 + 1;

                    AddQuad(triangles, i0, i1, i2, i3, clockwise);
                }
            }
        }

        void AddSideFaces(List<int> triangles, int py, int px, int sizeY, int sizeX, int yMin, int xMin, int offset, bool clockwise=true)
        {
            int ly, lx;

            // Build front face 
            if (py == (subMeshPatchSize - 1))
            {
                for (int x = 0; x < sizeX; x++)
                {
                    ly = sizeY;
                    lx = xMin + x;

                    if (invalidMask[ly, lx] || invalidMask[ly, lx + 1])
                        continue;

                    int i0 = sizeY * (sizeX + 1) + x; // Top left
                    int i1 = i0 + 1; // Top right
                    int i2 = i0 + offset; // Bottom left
                    int i3 = i1 + offset; // Bottom right

                    AddQuad(triangles, i0, i1, i2, i3, clockwise);
                    AddQuad(triangles, i0, i1, i2, i3, !clockwise);

                }
            }


            // Build back face 
            if (py == 0)
            {
                for (int x = 0; x < sizeX; x++)
                {
                    ly = 0;
                    lx = xMin + x;

                    if (invalidMask[ly, lx] || invalidMask[ly, lx + 1])
                        continue;

                    int i0 = x; // Top left
                    int i1 = i0 + 1; // Top right
                    int i2 = i0 + offset; // Bottom left
                    int i3 = i1 + offset; // Bottom right

                    AddQuad(triangles, i0, i1, i2, i3, clockwise);
                    AddQuad(triangles, i0, i1, i2, i3, !clockwise);
                }
            }


            // Build left face
            if (px == 0)
            {
                for (int y = 0; y < sizeY; y++)
                {
                    ly = yMin + y;
                    lx = 0;

                    if (invalidMask[ly, lx] || invalidMask[ly + 1, lx])
                        continue;

                    int i0 = (y + 1) * (sizeX + 1); // Top Right
                    int i1 = y * (sizeX + 1); // Top left
                    int i2 = i0 + offset; // Bottom right
                    int i3 = i1 + offset; // Bottom left

                    AddQuad(triangles, i0, i1, i2, i3, clockwise);
                    AddQuad(triangles, i0, i1, i2, i3, !clockwise);
                }
            }


            // Build right face 
            if (px == (subMeshPatchSize - 1))
            {
                for (int y = 0; y < sizeY; y++)
                {
                    ly = yMin + y;
                    lx = sizeX;

                    if (invalidMask[ly, lx] || invalidMask[ly + 1, lx])
                        continue;

                    int i0 = (y + 1) * (sizeX + 1) + sizeX; // Top left
                    int i1 = y * (sizeX + 1) + sizeX; // Top right
                    int i2 = i0 + offset; // Bottom left
                    int i3 = i1 + offset; // Bottom right

                    AddQuad(triangles, i0, i1, i2, i3, clockwise);
                    AddQuad(triangles, i0, i1, i2, i3, !clockwise);
                }
            }

        }


        void AddInteriorFaces(List<int> triangles, int sizeY, int sizeX, int yMin, int xMin, int offset)
        {
            int ly, lx;

            for (int y = 0; y < sizeY; y++)
            {
                for (int x = 0; x < sizeX; x++)
                {
                    ly = yMin + y;
                    lx = xMin + x;

                    int i0 = y * (sizeX + 1) + x;
                    int i1 = i0 + 1;
                    int i2 = i0 + (sizeX + 1);
                    int i3 = i2 + 1;

                    // Ignore if all the vertices are valid
                    if (!invalidMask[ly, lx] && !invalidMask[ly + 1, lx] && !invalidMask[ly, lx + 1] && !invalidMask[ly + 1, lx + 1])
                        continue;

                    // Ignore if all the vertices are invalid
                    if (invalidMask[ly, lx] && invalidMask[ly + 1, lx] && invalidMask[ly, lx + 1] && invalidMask[ly + 1, lx + 1])
                        continue;

                    // Build left side wall
                    if (!invalidMask[ly, lx] && !invalidMask[ly + 1, lx])
                    {
                        AddQuad(triangles, i2, i0, i2 + offset, i0 + offset, true);
                        AddQuad(triangles, i2, i0, i2 + offset, i0 + offset, false);
                    }

                    // Build right side wall
                    if (!invalidMask[ly, lx + 1] && !invalidMask[ly + 1, lx + 1])
                    {
                        AddQuad(triangles, i3, i1, i3 + offset, i1 + offset, true);
                        AddQuad(triangles, i3, i1, i3 + offset, i1 + offset, false);
                    }

                    // Build front side wall
                    if (!invalidMask[ly + 1, lx] && !invalidMask[ly + 1, lx + 1])
                    {
                        AddQuad(triangles, i2, i3, i2 + offset, i3 + offset, true);
                        AddQuad(triangles, i2, i3, i2 + offset, i3 + offset, false);
                    }

                    // Build back side wall
                    if (!invalidMask[ly, lx] && !invalidMask[ly, lx + 1])
                    {
                        AddQuad(triangles, i0, i1, i0 + offset, i1 + offset, true);
                        AddQuad(triangles, i0, i1, i0 + offset, i1 + offset, false);
                    }
                }
            }
        }

        async void AddQuad(List<int> triangles, int i0, int i1, int i2, int i3, bool clockwise = true)
        {
            if (clockwise)
            {
                // Triangle 1
                triangles.Add(i0); // Bottom left
                triangles.Add(i1); // Top left
                triangles.Add(i2); // Bottom right

                // Triangle 2
                triangles.Add(i1);
                triangles.Add(i3);
                triangles.Add(i2);
            }
            else
            {
                // Triangle 1
                triangles.Add(i0); // Bottom left
                triangles.Add(i2); // Top left
                triangles.Add(i1); // Bottom right

                // Triangle 2
                triangles.Add(i1);
                triangles.Add(i2);
                triangles.Add(i3);
            }
        }

    }

    /***
    async Color[] AddColorsToVertices(Vector3[] vertices, int sizeX, int sizeY, int offset)
    {
        Color[] colors = new Color[vertices.Length];

        float minHeight = (float)minWaterDepth;
        float maxHeight = (float)maxWaterDepth;

        int topCount = (sizeX + 1) * (sizeY + 1);

        // Step 2: Assign colors
        for (int i = 0; i < vertices.Length; i++)
        {
            if (i < topCount)
            {
                float normalized = Mathf.InverseLerp(minHeight, maxHeight, vertices[i].y);
                colors[i] = Color.Lerp(new Color(0.1f, 0.2f, 1f), Color.cyan, normalized); // Surface gradient
                // colors[i] = Color.Lerp(new Color(0.1f, 0.2f, 1f), new Color(0.1f, 0.2f, 0.2f), normalized); // Surface gradient

            }
            else
            {
                colors[i] = new Color(0.05f, 0.1f, 0.3f); // Bottom face or wall = deep blue
                // colors[i] = new Color(0.05f, 0.1f, 1f); // Bottom face or wall = deep blue

            }
        }

        return colors;
    }
    ***/
}


/***
double alt = 230; // If you have ECEF.Z, use it here for full 3D positioning
double3 wgsPos = new double3(wgs2D.x, wgs2D.y, alt);

GameObject marker = Instantiate(visPrefab);
marker.transform.SetParent(transform.parent, false);
var anchor = marker.AddComponent<CesiumGlobeAnchor>();
anchor.longitudeLatitudeHeight = wgsPos;
Transform markerTransform = marker.transform;
double3 scale = anchor.scaleEastUpNorth;
double3 newScale = new double3(scale.x, data.waterDepthMatrix[y, x], scale.z);
anchor.scaleEastUpNorth = newScale;
// marker.transform.localScale.z = marker.transform.localScale.z + waterDepthMatrix[y, x];
marker.SetActive(true);
***/
// Optional: Scale or color the prefab based on waterDepthMatrix[y, x]

/***
    void GetTerrainHeight(double2 wgs2D)
    {

    }

    public async Task SampleHeightAndPlaceMarker(double lon, double lat)
    {

    }
***/