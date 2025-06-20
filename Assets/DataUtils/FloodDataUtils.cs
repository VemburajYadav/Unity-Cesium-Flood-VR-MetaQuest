using UnityEngine;
using System.Collections;
using System.Collections.Generic;
using Unity.Mathematics;
using CesiumForUnity;

namespace DataUtils
{
    namespace FloodDataUtils
    {
        public class FloodSimulationData
        {
            public int height;
            public int width;
            public double2[,] ecefMatrix;
            public double2[,] wgs84Matrix;
            public double2[,] srcCrsMatrix;
            public double[,] waterDepthMatrix;
            public bool[,] invalidMask;
        }
    }
}