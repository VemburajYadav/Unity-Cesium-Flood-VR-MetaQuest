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


public class FloodInteraction : MonoBehaviour
{
    private bool isMeshReady = false;
    private FloodVisualizer visualizer;
    private List<GameObject> subMeshes = new List<GameObject>();
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    async void Start()
    {
        visualizer = GetComponent<FloodVisualizer>();

    }

    // Update is called once per frame
    void Update()
    {
        if (visualizer != null)
        {
            if (visualizer.isMeshReady)
            {
                // If user has just released Button A of right controller in this frame
                // make the mesh appear or disappear
                if (OVRInput.GetUp(OVRInput.Button.One))
                {
                    ToggleMeshVisibility();
                }
            }
        }
    }

    void ToggleMeshVisibility()
    {
        // Get all child transforms and filter by name
        subMeshes = GetComponentsInChildren<Transform>(true) // "true" includes inactive GameObjects
            .Where(t => t.name.StartsWith("SubMeshContainer_"))
            .Select(t => t.gameObject)
            .ToList();

        Debug.Log($"Found {subMeshes.Count} submeshes");

        foreach (GameObject subMesh in subMeshes)
        {
            bool currentState = subMesh.activeSelf;
            subMesh.SetActive(!currentState);
        }
        Debug.Log("Activated all submeshes");
    }
}
