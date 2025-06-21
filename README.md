# 🌍 Immersive 3D Flood Data Visualization in Unity for Meta Quest

This Unity project delivers a highly immersive 3D visualization of real-world flood data, designed specifically for **VR on Meta Quest 3**. Built using [Cesium for Unity](https://cesium.com/learn/unity/), it renders high-fidelity, globe-scale terrain and cityscapes—including [Photorealisitic 3D Tiles](https://developers.google.com/maps/documentation/tile/3d-tiles) from Google Earth and [OpenStreetMap building](https://www.openstreetmap.org/#map=13/51.94691/6.97400)—to recreate flooded environments with geospatial accuracy.

Users can **walk, fly, and explore in full virtual reality**, experiencing flood impacts from a street-level or aerial perspective. The integration of **Cesium’s double-precision geospatial engine** with Unity’s XR platform ensures both global-scale navigation and local immersion are fluid and precise.

---

## 🎬 Demo Video
[![General Demo](Thumbnails/thumbnail1.png)](https://drive.google.com/file/d/14pdGawrNnOZDor-FlxJd3zCl0w29m3FF/view?usp=sharing)

---

## 📌 Getting Started

Before diving into the project, complete the following setup steps to configure your environment:

### 1. Cesium for Unity Setup

👉 Follow the official **Cesium for Unity Quickstart** guide:  
[Cesium for Unity Quickstart](https://cesium.com/learn/unity/unity-quickstart/)

This will walk you through:

- Importing the Cesium for Unity packages
- Creating or logging into a [Cesium ion](https://cesium.com/ion/) account
- Generating an Access Token
- Adding the Access Token to your Unity Project

### 2. XR Setup for Meta Quest (Unity OpenXR)

👉 Follow the official **Meta XR Unity Project Setup** documentation:  
[Set up Unity for XR development](https://developers.meta.com/horizon/documentation/unity/unity-project-setup)

This guide covers project configuration for Meta Quest support, including:

- Enabling XR Plugin Management in Project Settings
- Setting up **Unity's OpenXR Plugin** for Meta Quest (do **not** use the Oculus XR Plugin)
- Configuring Android build settings (e.g., target SDK, permissions)
- Enabling hand/controller input profiles for Quest

---

## 🗺 Project Overview

### Main Features

- **Global-Scale Geospatial Visualization**: Uses **Cesium World Terrain**, **OSM Buildings**, and optionally **Photogrammetric 3D Tiles** (via Google Earth, if available) for highly realistic terrain and urban structure rendering.
- **Flood Data Rendering**: Visualizes flood depth data from `.tif` files processed into binary format.
- **Immersive XR Navigation**: Supports walking and flying through the scene with Meta Quest controllers.
- **Flood Interaction**: Simple toggle to show/hide water; extensible for more complex interactivity.

---


## 🌊 Flood Data Pipeline

Flood data starts with a `.tif` file (e.g., `flood_data.tif`) and is converted into binary format using an **external Python pipeline**.

### Output Files (per flood dataset):

- `wgs84_matrix.bin`: Latitude & longitude grid (EPSG:4326)
- `ecef_matrix.bin`: Earth-Centered, Earth-Fixed coordinates (ECEF)
- `src_crs_matrix.bin`: Original Coordinates in the TIF's source Coordiante Reference System
- `water_depth_matrix.bin`: Water depth grid
- `invalid_mask.bin`: Binary mask indicating invalid or missing grid points

> 📁 Place the resulting folder (e.g., `flood_data/`) inside `Assets/StreamingAssets/`.

---

## 🔍 Flood Visualization Details

The `FloodVisualizer.cs` script generates a mesh representation of the flood area:

- A **256×256** flood grid is divided into **16×16 submeshes** for better precision and performance.
- Each submesh uses a `CesiumGlobeAnchor` to position it accurately on the globe.
- Vertices are stored **relative to the anchor origin** to avoid floating-point precision issues in Unity.
- A custom ShaderGraph-based **FloodShader** material enables dynamic control over per-vertex color and alpha.

> ✅ Submeshes + anchored-relative coordinates ensure rendering stability across large world scales.  
> 🔧 **TODO**: Improve color mapping to visually distinguish flood depths using gradient-based colorization.

---

## 🕹 XR Navigation and Interaction

Implemented in `SceneNavigator.cs` and `FloodInteraction.cs`.

### 🎮 Controls

| **Input**                 | **Action**                                         |
|--------------------------|----------------------------------------------------|
| Right Thumbstick         | Move in camera's forward/right direction           |
| Left Thumbstick          | Move up/down                                       |
| Left/Right Index Trigger | Control movement speed (analog, pressure-based)    |
| Left/Right Hand Trigger  | Rotate view left/right                             |
| Right 'A' Button         | Toggle flood visibility (show/hide water mesh)     |

> 🚀 XR support is enabled via **OpenXR** and tested on **Meta Quest 3**.  
> 🔧 Make sure to configure XR settings correctly via **Project Settings** as per the [Meta XR Unity Setup Guide](https://developers.meta.com/horizon/documentation/unity/unity-project-setup).

---

## 🔮 Planned Features / TODO

- [ ] Improve ShaderGraph visualization using colormap gradients
- [ ] Timeline slider for visualizing flooding over time
- [ ] Region-based highlighting and selection
- [ ] Add interactive pointer-based tools (e.g., depth probe, info overlays)
