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

public class MoveCube : MonoBehaviour
{
    // public Vector3 velocity = new Vector3(0f, -1f, 0f); // Set your desired velocity in the Inspector
    CesiumGlobeAnchor anchor;
    double3 ecefPosition;
    double3 geodeticPosition;

    void Start()
    {
        anchor = GetComponent<CesiumGlobeAnchor>();
        ecefPosition = anchor.positionGlobeFixed;
        geodeticPosition = anchor.longitudeLatitudeHeight;

        Debug.Log($"ECEF Position: {ecefPosition}");
        Debug.Log($"Geodetic Coordinates: {geodeticPosition}");
    }

    void FixedUpdate()
    {

    }


}
