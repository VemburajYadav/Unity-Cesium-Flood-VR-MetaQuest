using UnityEngine;
using System.Collections.Generic;

public class ProxyColliderManager : MonoBehaviour
{
    // Dictionary to track original tiles and their proxy colliders
    private Dictionary<GameObject, GameObject> tileToProxyMap = new Dictionary<GameObject, GameObject>();

    // Layer specifically for proxy colliders
    public int proxyColliderLayer = 8; // Customize this to an appropriate layer in your project

    // Parent transform to organize proxy objects
    private Transform proxyParent;

    // Bounding box for proxy creation
    public Vector3 boundsMin = new Vector3(-10000f, -10000f, -10000f);
    public Vector3 boundsMax = new Vector3(10000f,10000f, 10000f);

    private void Awake()
    {
        // Create a parent object to keep the hierarchy clean
        proxyParent = new GameObject("ProxyColliders").transform;
        proxyParent.SetParent(transform.parent, false);
    }

    // Check if a position is within the specified bounds
    private bool IsWithinBounds(Vector3 position)
    {
        return position.x >= boundsMin.x && position.x <= boundsMax.x &&
               position.y >= boundsMin.y && position.y <= boundsMax.y &&
               position.z >= boundsMin.z && position.z <= boundsMax.z;
    }

    // Call this when a new tile is loaded/activated
    public void CreateProxyFor(GameObject tileMeshObject)
    {
        // Skip if we already have a proxy for this tile
        if (tileToProxyMap.ContainsKey(tileMeshObject))
            return;

        MeshCollider originalCollider = tileMeshObject.GetComponent<MeshCollider>();
        MeshFilter originalMeshFilter = tileMeshObject.GetComponent<MeshFilter>();

        // Make sure the original has the components we need
        if (originalCollider == null || originalMeshFilter == null)
        {
            Debug.LogWarning($"Tile {tileMeshObject.name} is missing required components for proxy creation");
            return;
        }

        if (IsWithinBounds(tileMeshObject.transform.position))
        {
            // Create the proxy GameObject
            GameObject proxy = new GameObject($"Proxy_{tileMeshObject.name}");
            proxy.transform.SetParent(proxyParent);

            // Match transform
            proxy.transform.position = tileMeshObject.transform.position;
            proxy.transform.rotation = tileMeshObject.transform.rotation;
            proxy.transform.localScale = tileMeshObject.transform.localScale;

            // Add collider with same properties
            MeshCollider proxyCollider = proxy.AddComponent<MeshCollider>();
            proxyCollider.sharedMesh = originalCollider.sharedMesh;
            proxyCollider.convex = originalCollider.convex;
            proxyCollider.isTrigger = originalCollider.isTrigger;
            proxyCollider.cookingOptions = originalCollider.cookingOptions;
            proxyCollider.material = originalCollider.material;

            // Set the layer
            proxy.layer = proxyColliderLayer;

            // Make it invisible but keep the collider active
            proxy.AddComponent<MeshFilter>().sharedMesh = originalMeshFilter.sharedMesh;
            MeshRenderer renderer = proxy.AddComponent<MeshRenderer>();
            renderer.enabled = true; // Keep it invisible

            // Store the mapping
            tileToProxyMap.Add(tileMeshObject, proxy);

            Debug.Log($"Created proxy collider for {tileMeshObject.name}");
        }

    }

    // Call this when a tile is about to be destroyed
    public void RetainProxyFor(GameObject tileMeshObject)
    {
        // Check if we have a proxy for this tile
        if (tileToProxyMap.TryGetValue(tileMeshObject, out GameObject proxy))
        {
            // The proxy will remain even when the original is destroyed
            Debug.Log($"Retaining proxy collider for {tileMeshObject.name}");
        }
    }

    // Call this when you want to remove a proxy
    public void RemoveProxyFor(GameObject tileMeshObject)
    {
        if (tileToProxyMap.TryGetValue(tileMeshObject, out GameObject proxy))
        {
            Destroy(proxy);
            tileToProxyMap.Remove(tileMeshObject);
            Debug.Log($"Removed proxy collider for {tileMeshObject.name}");
        }
    }

    // Call this method to create proxies for all current active tiles
    public void CreateProxiesForActiveTiles(List<GameObject> activeTiles)
    {
        foreach (GameObject tile in activeTiles)
        {
            CreateProxyFor(tile);
        }
    }

    // Optional: Clean up any proxies whose originals no longer exist
    public void CleanupOrphanedProxies()
    {
        List<GameObject> tilesToRemove = new List<GameObject>();

        foreach (var pair in tileToProxyMap)
        {
            if (pair.Key == null)
            {
                Destroy(pair.Value);
                tilesToRemove.Add(pair.Key);
            }
        }

        foreach (GameObject tile in tilesToRemove)
        {
            tileToProxyMap.Remove(tile);
        }
    }
}
