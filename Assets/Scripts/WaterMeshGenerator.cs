using UnityEngine;
using System.Collections;
using System.Collections.Generic;

[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class WaterMeshGenerator : MonoBehaviour
{
    public int sizeX = 11;
    public int sizeZ = 11;
    public float spacing = 1f;
    public float[,] heights; // Optional: Fill this from outside if needed
    public bool[,] validMask;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        if (heights == null)
        {
            heights = new float[sizeX + 1, sizeZ + 1];
            // Fill dummy heights (e.g., gradient + noise)
            for (int x = 0; x <= sizeX; x++)
            {
                for (int z = 0; z <= sizeZ; z++)
                {
                    //float height = Random.Range(2f, 20f); // random water height
                    heights[x, z] = Mathf.PerlinNoise(x * 0.2f, z * 0.2f) * 10f;
                }
            }
        }

        validMask = new bool[sizeX + 1, sizeZ + 1];

        // Mark all valid by default
        for (int x = 0; x <= sizeX; x++)
        {
            for (int z = 0; z <= sizeZ; z++)
                validMask[x, z] = true;
        }

        // Invalidate some region (simulate buildings)
        validMask[3, 3] = false;
        validMask[3, 4] = false;
        validMask[4, 3] = false;
        validMask[4, 4] = false;
        validMask[5, 3] = false;
        validMask[5, 4] = false;
        validMask[4, 5] = false;

        // Invalid left side vertex
        validMask[0, 7] = false;
        // Invalid right side vertex
        validMask[10, 5] = false;        
        // Invalid top side vertex
        validMask[3, 10] = false;        
        // Invalid bottom side vertex
        validMask[8, 0] = false;

        GenerateMesh();

        /***
        Mesh mesh = new Mesh();
        mesh.name = "WaterQuad";

        Vector3 bot0 = new Vector3(-2f, 0f, -2f);
        Vector3 bot1 = new Vector3(-2f, 0f, 2f);
        Vector3 bot2 = new Vector3(2f, 0f, 2f);
        Vector3 bot3 = new Vector3(2f, 0f, -2f);

        // Dummy "heightmap" values
        float[] dummyHeights = new float[] { 5f, 10f, 10f, 5f };

        Vector3 top0 = new Vector3(bot0.x, dummyHeights[0], bot0.z);
        Vector3 top1 = new Vector3(bot1.x, dummyHeights[1], bot1.z);
        Vector3 top2 = new Vector3(bot2.x, dummyHeights[2], bot2.z);
        Vector3 top3 = new Vector3(bot3.x, dummyHeights[3], bot3.z);

        Vector3[] vertices = new Vector3[]
        {
            top0, top1, top2, top3, // 0-3
            bot0, bot1, bot2, bot3  // 4-7
        };


        int[] triangles = new int[]
        {
            // Top face
            0, 1, 2,
            0, 2, 3,

            // Bottom face
            4, 6, 5,
            4, 7, 6,

            // Front face
            0, 3, 4,
            4, 3, 7,

            // Back face
            1, 5, 2,
            5, 6, 2,

            // Left face
            5, 1, 0,
            5, 0, 4,

            // Right face
            6, 3, 2,
            6, 7, 3
        };

        mesh.vertices = vertices;
        mesh.triangles = triangles;
        mesh.RecalculateNormals();
        GetComponent<MeshFilter>().mesh = mesh;
        ***/
    }

    void GenerateMesh()
    {
        int vertCountPerSide = (sizeX + 1) * (sizeZ + 1);
        int totalVerts = vertCountPerSide * 2; // top and bottom

        Vector3[] vertices = new Vector3[totalVerts];
        List<int> triangles = new List<int>();

        // Create top and bottom vertices
        for (int x = 0; x <= sizeX; x++)
        {
            for (int z = 0; z <= sizeZ; z++)
            {
                int i = x * (sizeZ + 1) + z;

                float height = heights[x, z];
                vertices[i] = new Vector3(x * spacing, height, z * spacing); // top
                vertices[i + vertCountPerSide] = new Vector3(x * spacing, 0, z * spacing); // bottom
            }
        }

        // Colors for vertices
        Color[] colors = AddColorsToVertices(vertices, sizeX, sizeZ, vertCountPerSide);

        // Build top surface triangles (clockwise from above)
        for (int x = 0; x < sizeX; x++)
        {
            for (int z = 0; z < sizeZ; z++)
            {
                if (!validMask[x, z] || !validMask[x + 1, z] || !validMask[x, z + 1] || !validMask[x + 1, z + 1])
                    continue;

                int i0 = x * (sizeZ + 1) + z;
                int i1 = i0 + 1;
                int i2 = i0 + (sizeZ + 1);
                int i3 = i2 + 1;

                // Triangle 1
                triangles.Add(i0); // Bottom left
                triangles.Add(i1); // Top left
                triangles.Add(i2); // Bottom right

                // Triangle 2
                triangles.Add(i2);
                triangles.Add(i1);
                triangles.Add(i3);
            }
        }

        // Build bottom surface triangles (clockwise from below)
        for (int x = 0; x < sizeX; x++)
        {
            for (int z = 0; z < sizeZ; z++)
            {
                if (!validMask[x, z] || !validMask[x + 1, z] || !validMask[x, z + 1] || !validMask[x + 1, z + 1])
                    continue;

                int i0 = x * (sizeZ + 1) + z + vertCountPerSide;
                int i1 = i0 + 1;
                int i2 = i0 + (sizeZ + 1);
                int i3 = i2 + 1;

                // Flip order for correct outward normals
                triangles.Add(i0);
                triangles.Add(i2);
                triangles.Add(i1);

                triangles.Add(i1);
                triangles.Add(i2);
                triangles.Add(i3);
            }
        }

        // Add side walls
        AddSideFaces(triangles, vertices, validMask, sizeX, sizeZ, vertCountPerSide);

        // Add Interior walls
        AddInteriorFaces(triangles, vertices, validMask, sizeX, sizeZ, vertCountPerSide);

        // Finalize mesh
        Mesh mesh = new Mesh();
        mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32; // In case we go big later
        mesh.vertices = vertices;
        mesh.triangles = triangles.ToArray();
        mesh.colors = colors;
        mesh.RecalculateNormals();            
        GetComponent<MeshFilter>().mesh = mesh;
    }

    Color[] AddColorsToVertices(Vector3[] vertices, int sizeX, int sizeZ, int offset)
    {
        Color[] colors = new Color[vertices.Length];

        float minHeight = float.MaxValue;
        float maxHeight = float.MinValue;
        int topCount = (sizeX + 1) * (sizeZ + 1);

        // Step 1: find min/max of the **top surface only**
        for (int i = 0; i < topCount; i++)
        {
            minHeight = Mathf.Min(minHeight, vertices[i].y);
            maxHeight = Mathf.Max(maxHeight, vertices[i].y);
        }

        // Step 2: Assign colors
        for (int i = 0; i < vertices.Length; i++)
        {
            /***
            float xNormalized = Mathf.InverseLerp(0f, sizeX, vertices[i].x);
            float zNormalized = Mathf.InverseLerp(0f, sizeZ, vertices[i].z);
            colors[i] = Color.Lerp(Color.red, Color.green, xNormalized); // Surface gradient
            ***/

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

    void AddInteriorFaces(List<int> triangles, Vector3[] vertices, bool[,] validMask, int sizeX, int sizeZ, int offset)
    {
        for (int x = 0; x < sizeX; x++)
        {
            for (int z = 0; z < sizeZ; z++)
            {
                int i0 = x * (sizeZ + 1) + z; // Bottom left
                int i1 = i0 + 1; // Top left
                int i2 = i0 + sizeZ + 1; // Bottom right
                int i3 = i2 + 1; // Top right

                // Ignore if all the vertices are valid
                if (validMask[x, z] && validMask[x + 1, z] && validMask[x, z + 1] && validMask[x + 1, z + 1])
                    continue;

                // Ignore if all the vertices are invalid
                if (!validMask[x, z] && !validMask[x + 1, z] && !validMask[x, z + 1] && !validMask[x + 1, z + 1])
                    continue;

                // Build left side wall
                if (validMask[x, z] && validMask[x, z + 1])
                {
                    triangles.Add(i0);
                    triangles.Add(i1);
                    triangles.Add(i0 + offset);

                    triangles.Add(i0 + offset);
                    triangles.Add(i1);
                    triangles.Add(i1 + offset);
                }

                // Build right side wall
                if (validMask[x + 1, z] && validMask[x + 1, z + 1])
                {
                    triangles.Add(i3);
                    triangles.Add(i2);
                    triangles.Add(i3 + offset);

                    triangles.Add(i3 + offset);
                    triangles.Add(i2);
                    triangles.Add(i2 + offset);
                }

                // Build front side wall
                if (validMask[x, z + 1] && validMask[x + 1, z + 1])
                {
                    triangles.Add(i1);
                    triangles.Add(i3);
                    triangles.Add(i1 + offset);

                    triangles.Add(i1 + offset);
                    triangles.Add(i3);
                    triangles.Add(i3 + offset);
                }

                // Build back side wall
                if (validMask[x, z] && validMask[x + 1, z])
                {
                    triangles.Add(i2);
                    triangles.Add(i0);
                    triangles.Add(i2 + offset);

                    triangles.Add(i2 + offset);
                    triangles.Add(i0);
                    triangles.Add(i0 + offset);
                }
            }
        }
    }

    void AddSideFaces(List<int> triangles, Vector3[] vertices, bool[,] validMask, int sizeX, int sizeZ, int offset)
    {
        // Build front face 
        for (int x = 0; x < sizeX; x++)
        {
            if (!validMask[x, 0] || !validMask[x + 1, 0])
                continue;

            int i0 = x * (sizeZ + 1); // Top left
            int i1 = i0 + sizeZ + 1; // Top right
            int i2 = i0 + offset; // Bottom left
            int i3 = i1 + offset; // Bottom right

            // Traingle 1
            triangles.Add(i0);
            triangles.Add(i1);
            triangles.Add(i2);

            // Traingle 2
            triangles.Add(i2);
            triangles.Add(i1);
            triangles.Add(i3);
        }

        // Build back face 
        for (int x = 0; x < sizeX; x++)
        {
            if (!validMask[x, sizeZ] || !validMask[x + 1, sizeZ])
                continue;

            int i0 = x * (sizeZ + 1) + sizeZ; // Top left
            int i1 = i0 + sizeZ + 1; // Top right
            int i2 = i0 + offset; // Bottom left
            int i3 = i1 + offset; // Bottom right

            // Traingle 1
            triangles.Add(i0);
            triangles.Add(i2);
            triangles.Add(i1);

            // Traingle 2
            triangles.Add(i2);
            triangles.Add(i3);
            triangles.Add(i1);
        }

        // Build left face 
        for (int z = 0; z < sizeZ; z++)
        {
            if (!validMask[0, z] || !validMask[0, z + 1])
                continue;

            int i0 = z; // Top Right
            int i1 = i0 + 1; // Top left
            int i2 = i0 + offset; // Bottom right
            int i3 = i1 + offset; // Bottom left

            // Traingle 1
            triangles.Add(i0);
            triangles.Add(i2);
            triangles.Add(i1);

            // Traingle 2
            triangles.Add(i2);
            triangles.Add(i3);
            triangles.Add(i1);
        }

        // Build right face 
        for (int z = 0; z < sizeZ; z++)
        {
            if (!validMask[sizeX, z] || !validMask[sizeX, z + 1])
                continue;

            int i0 = sizeX * (sizeZ + 1) + z; // Top left
            int i1 = i0 + 1; // Top right
            int i2 = i0 + offset; // Bottom left
            int i3 = i1 + offset; // Bottom right

            // Traingle 1
            triangles.Add(i0);
            triangles.Add(i1);
            triangles.Add(i2);

            // Traingle 2
            triangles.Add(i2);
            triangles.Add(i1);
            triangles.Add(i3);
        }
    }


    // Update is called once per frame
    void Update()
    {
        /***
        Mesh mesh = GetComponent<MeshFilter>().mesh;
        Vector3[] vertices = mesh.vertices;
        for (int i = 0; i < vertices.Length; i++)
        {
            vertices[i].y = Mathf.Sin(Time.time + i) * 0.2f;
        }
        mesh.vertices = vertices;
        mesh.RecalculateNormals();
        GetComponent<MeshFilter>().mesh = mesh;
        ***/
    }
}
