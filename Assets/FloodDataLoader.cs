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
using CesiumForUnity;
using Newtonsoft.Json; // Install Newtonsoft.Json via Unity Package Manager
using DataUtils.FloodDataUtils;
using System.Threading.Tasks;

public class FloodDataLoader : MonoBehaviour
{
    private string folderName1 = "Processed_Samples/gt_16_477871_5441591"; // Folder inside StreamingAssets
    private string folderName2 = "Processed_Samples/gt_16_477871_5442872"; // Folder inside StreamingAssets
    private string folderName3 = "Processed_Samples/gt_16_477871_5444154"; // Folder inside StreamingAssets
    private string folderName4 = "Processed_Samples/gt_16_479152_5440310"; // Folder inside StreamingAssets
    private string folderName5 = "Processed_Samples/gt_16_479152_5441591"; // Folder inside StreamingAssets

    private string[] folderNames = new string[]
    {
    "Processed_Samples/gt_16_477871_5441591",
    "Processed_Samples/gt_16_477871_5442872",
    "Processed_Samples/gt_16_477871_5444154",
    "Processed_Samples/gt_16_479152_5440310",
    "Processed_Samples/gt_16_479152_5441591"
    };
    
    private int numFolders = 5;
    public bool[] isDataReady;
    public int height;
    public int width;

    public FloodSimulationData[] data;

    public delegate void OnDataLoaded(FloodSimulationData data);
    public event OnDataLoaded DataLoaded;

    [Serializable]
    public class Metadata
    {
        public int[] shape;
        public string dtype;
        public string mask_dtype;
        public string crs;
        public double[] transform;
    }

    async void Start()
    {
        isDataReady = new bool[numFolders];
        data = new FloodSimulationData[numFolders];

        for (int i = 0; i < 1; i++)
        {
            isDataReady[i] = false;
            await LoadFloodDataAsync(folderNames[4], i);
            isDataReady[i] = true;
            Debug.Log("Flood data loaded successfully!");
            // PrintSampleData();
            DataLoaded?.Invoke(data[i]);
        }
    }



    async Task LoadFloodDataAsync(string folderName, int index)
    {
        string path = Path.Combine(Application.streamingAssetsPath, folderName);

        // Run file loading on a background thread
        data[index] = await Task.Run(() =>
        {
            string metaJson = File.ReadAllText(Path.Combine(path, "flood_data_meta.json"));
            Metadata meta = JsonConvert.DeserializeObject<Metadata>(metaJson);

            // Debug.Log($"Grid size: {meta.shape[0]}, {meta.shape[1]}");
            var result = new FloodSimulationData
            {
                height = meta.shape[0],
                width = meta.shape[1],
                ecefMatrix = LoadDouble2Matrix(Path.Combine(path, "ecef_matrix.bin"), meta.shape[0], meta.shape[1]),
                wgs84Matrix = LoadDouble2Matrix(Path.Combine(path, "wgs84_matrix.bin"), meta.shape[0], meta.shape[1]),
                srcCrsMatrix = LoadDouble2Matrix(Path.Combine(path, "src_crs_matrix.bin"), meta.shape[0], meta.shape[1]),
                waterDepthMatrix = LoadScalarMatrix(Path.Combine(path, "water_depth_matrix.bin"), meta.shape[0], meta.shape[1]),
                invalidMask = LoadBoolMatrix(Path.Combine(path, "invalid_mask.bin"), meta.shape[0], meta.shape[1])
            };

            return result;
        });
    }


    double2[,] LoadDouble2Matrix(string filePath, int height, int width)
    {
        byte[] raw = File.ReadAllBytes(filePath);
        int size = height * width * 2;
        double[] buffer = new double[size];
        Buffer.BlockCopy(raw, 0, buffer, 0, raw.Length);

        double2[,] result = new double2[height, width];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                int i = (y * width + x) * 2;
                double xVal = (double)buffer[i];
                double yVal = (double)buffer[i + 1];
                result[y, x] = new double2(xVal, yVal);
            }
        }
        return result;
    }

    double[,] LoadScalarMatrix(string filePath, int height, int width)
    {
        byte[] raw = File.ReadAllBytes(filePath);
        int size = height * width;
        double[] buffer = new double[size];
        Buffer.BlockCopy(raw, 0, buffer, 0, raw.Length);

        double[,] result = new double[height, width];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                int i = y * width + x;
                result[y, x] = (double)buffer[i];
            }
        }
        return result;
    }

    bool[,] LoadBoolMatrix(string filePath, int height, int width)
    {
        byte[] raw = File.ReadAllBytes(filePath);
        bool[,] result = new bool[height, width];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                result[y, x] = raw[y * width + x] != 0;
            }
        }
        return result;
    }

    /***
    public void PrintSampleData(int sampleWidth = 5, int sampleHeight = 5)
    {
        int maxX = Mathf.Min(sampleWidth, data.width);
        int maxY = Mathf.Min(sampleHeight, data.height);

        Debug.Log($"--- Sample Flood Data [{maxY}x{maxX}] ---");

        for (int y = 0; y < maxY; y++)
        {
            for (int x = 0; x < maxX; x++)
            {
                var ecef = data.ecefMatrix[y, x];
                var wgs = data.wgs84Matrix[y, x];
                var crs = data.srcCrsMatrix[y, x];
                var depth = data.waterDepthMatrix[y, x];
                var isInvalid = data.invalidMask[y, x];

                Debug.Log($"[y={y}, x={x}] ECEF=({ecef.x:F5}, {ecef.y:F5}) | WGS84=({wgs.x:F5}, {wgs.y:F5}) | " +
                          $"SRC_CRS=({crs.x:F5}, {crs.y:F5}) | Depth={depth:F5} | Invalid={isInvalid}");
            }
        }

        Debug.Log("--- End of Sample ---");
    }
    ***/

    /***
    void VisualizeFloodPoints(GameObject prefab)
    {
        for (int y = 0; y < 10; y++)
        {
            for (int x = 0; x < 10; x++)
            {
                if (invalidMask[y, x]) continue;

                double2 ecef2D = ecefMatrix[y, x];
                double z = 4396725; // If you have ECEF.Z, use it here for full 3D positioning
                double3 ecefPos = new double3(ecef2D.x, ecef2D.y, z);

                GameObject marker = Instantiate(prefab);
                marker.transform.SetParent(transform.parent, false);
                var anchor = marker.AddComponent<CesiumGlobeAnchor>();
                anchor.positionGlobeFixed = ecefPos;
                marker.SetActive(true);

                // Optional: Scale or color the prefab based on waterDepthMatrix[y, x]
            }
        }
    }
    ***/

}

