using UnityEngine;
using System.Collections;
using System.Collections.Generic;

public class ControllerScript : MonoBehaviour
{
    public Camera sceneCamera;
    private Vector3 targetPosition;
    private Quaternion targetRotation;
    private float step;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        transform.position = sceneCamera.transform.position + sceneCamera.transform.forward * 3.0f;
    }

    // Update is called once per frame
    void Update()
    {
        // Define step value for animation
        step = 5.0f * Time.deltaTime;


        // While user holds the right index trigger, center the cube and turn it to face user
        if (OVRInput.Get(OVRInput.RawButton.RIndexTrigger)) centerCube();

        // While thumbstick of right controller is currently pressed to the left
        // rotate cube to the left
        if (OVRInput.Get(OVRInput.RawButton.RThumbstickLeft)) transform.Rotate(0, 5.0f * step, 0);

        // While thumbstick of right controller is currently pressed to the right
        // rotate cube to the right
        if (OVRInput.Get(OVRInput.RawButton.RThumbstickRight)) transform.Rotate(0, -5.0f * step, 0);

        // While thumbstick of right controller is currently pressed to up
        // rotate cube Upwards
        if (OVRInput.Get(OVRInput.RawButton.RThumbstickUp)) transform.Rotate(5.0f * step, 0, 0);

        // While thumbstick of right controller is currently pressed to down
        // rotate cube Downwards
        if (OVRInput.Get(OVRInput.RawButton.RThumbstickDown)) transform.Rotate(-5.0f * step, 0, 0);

        // If user has just released Button A of right controller in this frame
        if (OVRInput.GetUp(OVRInput.Button.One))
        {
            // Play short haptic on right controller
            OVRInput.SetControllerVibration(1, 1, OVRInput.Controller.LTouch);
        }

        // While user holds the left hand trigger
        if (OVRInput.Get(OVRInput.Axis1D.PrimaryHandTrigger) > 0.0f)
        {
            // Assign left controller's position and rotation to cube
            transform.position = OVRInput.GetLocalControllerPosition(OVRInput.Controller.LTouch);
            transform.rotation = OVRInput.GetLocalControllerRotation(OVRInput.Controller.LTouch);
        }


    }

    void centerCube()
    {
        targetPosition = sceneCamera.transform.position + sceneCamera.transform.forward * 0.3f;
        targetRotation = Quaternion.LookRotation(transform.position - sceneCamera.transform.position);

        transform.position = Vector3.Lerp(transform.position, targetPosition, step);
        transform.rotation = Quaternion.Slerp(transform.rotation, targetRotation, step);
    }
}
