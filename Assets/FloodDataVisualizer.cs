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

public class FloodDataVisualizer : MonoBehaviour
{
    public GameObject visPrefab;
    public Cesium3DTileset terrainTileset;

    private FloodDataLoader dataLoader;
    private int height;
    private int width;

    private double2[,] ecefMatrix;
    private double2[,] wgs84Matrix;
    private double2[,] srcCrsMatrix;
    private double[,] waterDepthMatrix;
    private bool[,] invalidMask;


    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        dataLoader = gameObject.GetComponent<FloodDataLoader>();

        // Find the sibling GameObject named "Cesium World Terrain"
        Transform parent = transform.parent;
        Transform cesiumTransform = parent.Find("Cesium World Terrain");
        terrainTileset = cesiumTransform.GetComponent<Cesium3DTileset>();

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

    void VisualizeFloodData(FloodSimulationData data)
    {
        int yMin = 0;
        int yMax = 50;
        int xMin = 0;
        int xMax = 50;

        for (int y = yMin; y < yMax; y+=1)
        {
            for (int x = xMin; x < xMax; x+=1)
            {
                if (data.invalidMask[y, x]) continue;
                double2 lonLat = data.wgs84Matrix[y, x];
                double3 queryPoint = new double3(lonLat.x, lonLat.y, 0);
                SampleTerrainHeightAndPlaceMarker(queryPoint, data.waterDepthMatrix[y, x]);
            }
        }
    }

    async void SampleTerrainHeightAndPlaceMarker(double3 queryPoint, double waterDepth)
    {
        // Query terrain height for this point
        var result = await terrainTileset.SampleHeightMostDetailed(new double3[] { queryPoint });
        // yield return CesiumForUnity.WaitForTask.WaitForTask(task);

        if (result == null || result.longitudeLatitudeHeightPositions == null || result.longitudeLatitudeHeightPositions.Length < 1)
        {
            Debug.LogWarning($"Failed to sample height at ({queryPoint.x}, {queryPoint.y})");
        }

        double3 wgs3D = result.longitudeLatitudeHeightPositions[0];
        Debug.Log($"Sampled Position: {wgs3D}");

        double offset = 0.1;
        GameObject marker = Instantiate(visPrefab);
        marker.transform.SetParent(transform.parent, false);
        var anchor = marker.AddComponent<CesiumGlobeAnchor>();
        Transform markerTransform = marker.transform;
        double3 scale = anchor.scaleEastUpNorth;
        double3 newScale = new double3(scale.x, waterDepth, scale.z);
        // double3 newScale = new double3(scale.x, 10.0, scale.z);
        anchor.scaleEastUpNorth = newScale;
        double3 wgs3D_surface = new double3(wgs3D.x, wgs3D.y, wgs3D.z + (newScale.y / 2.0) + offset);
        anchor.longitudeLatitudeHeight = wgs3D_surface;

        Quaternion rotation = anchor.rotationEastUpNorth;
        Debug.Log($"Rotation: {rotation}");

        marker.SetActive(true);

    }

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