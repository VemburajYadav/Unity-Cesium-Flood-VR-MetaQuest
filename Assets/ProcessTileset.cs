using UnityEngine;
using CesiumForUnity;

public class ProcessTileset : MonoBehaviour
{
    private Cesium3DTileset tileset;
    private ProxyColliderManager proxyManager;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        tileset = gameObject.GetComponent<Cesium3DTileset>();
        tileset.OnTileGameObjectCreated += CheckLoadedTile;
        proxyManager = gameObject.GetComponent<ProxyColliderManager>();
    }

    // Update is called once per frame
    void Update()
    {
        
    }

    private void CheckLoadedTile(GameObject tileGameObject)
    {
        Debug.Log("Loaded Game Object: " +  tileGameObject.name);
        Debug.Log("Loaded Game Object (Child Count): " + tileGameObject.transform.childCount);

        Transform childTransform = tileGameObject.transform.GetChild(0);
        GameObject childGameObject = childTransform.gameObject;
        Debug.Log("Child Game Object: " + childGameObject.name);

        proxyManager.CreateProxyFor(childGameObject);
    }
}
