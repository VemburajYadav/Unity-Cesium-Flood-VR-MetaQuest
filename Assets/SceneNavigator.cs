using UnityEngine;
using System.Collections;
using System.Collections.Generic;
using CesiumForUnity;

public class SceneNavigator : MonoBehaviour
{
    [SerializeField]
    private Camera sceneCamera;
    private CharacterController controller;
    private Transform cameraTransform;
    private bool playerGrounded;

    void Start()
    {
        controller = gameObject.GetComponent<CharacterController>();
        cameraTransform = sceneCamera.transform;
    }

    // Update is called once per frame
    void Update()
    {
        float horizontalMovement = 1.0f;
        float verticalMovement = 1.0f;
        float horizontalSpeedUpMin = 1.0f;
        float horizontalSpeedUpMax = 10.0f;
        float verticalSpeedUpMin = 1.0f;
        float verticalSpeedUpMax = 5.0f;

        // Extent to which the triggers are pressed
        float leftIndexTriggerProgress = OVRInput.Get(OVRInput.Axis1D.PrimaryIndexTrigger);
        float rightIndexTriggerProgress = OVRInput.Get(OVRInput.Axis1D.SecondaryIndexTrigger);
        float leftHandTriggerProgress = OVRInput.Get(OVRInput.Axis1D.PrimaryHandTrigger);
        float rightHandTriggerProgress = OVRInput.Get(OVRInput.Axis1D.SecondaryHandTrigger);

        // Map the right index trigger to speed up or speed down the horizontal movement 
        if (rightIndexTriggerProgress > 0.0f)
        {
            horizontalMovement = horizontalMovement * (horizontalSpeedUpMin + rightIndexTriggerProgress * (horizontalSpeedUpMax - horizontalSpeedUpMin));
        }

        // Map the left index trigger to speed up or speed down the vertical movement 
        if (leftIndexTriggerProgress > 0.0f)
        {
            verticalMovement = verticalMovement * (verticalSpeedUpMin + leftIndexTriggerProgress * (verticalSpeedUpMax - verticalSpeedUpMin));
        }

        playerGrounded = controller.isGrounded;

        // Rotate the camera (left or right) based on Hand Triggersd
        if (rightHandTriggerProgress > 0.0f) transform.Rotate(0f, 1f, 0f); // Rotate the TrackingSpace!
        if (leftHandTriggerProgress > 0.0f) transform.Rotate(0f, -1f, 0f); // Rotate the TrackingSpace!

        // Move in the horizontal plane (plane formed by camera's forward and right axis) based on Right Thumbstick movement
        Vector2 rightThumbstickInput = OVRInput.Get(OVRInput.Axis2D.SecondaryThumbstick);
        controller.Move((cameraTransform.forward * rightThumbstickInput.y + cameraTransform.right * rightThumbstickInput.x) * horizontalMovement);

        // Keeps the player on the ground until and unless LeftThumbStick is pressed to move vertically 
        if (playerGrounded)
        {
            controller.Move(-Vector3.up * 5f);
        }

        // While thumbstick of left controller is currently pressed to Up
        // move up
        if (OVRInput.Get(OVRInput.RawButton.LThumbstickUp))
        {
            controller.Move(cameraTransform.up * verticalMovement);
        }

        // While thumbstick of left controller is currently pressed to Down
        // move down
        if (OVRInput.Get(OVRInput.RawButton.LThumbstickDown))
        {
            controller.Move(-1f * cameraTransform.up * verticalMovement);
        }
    }


}
