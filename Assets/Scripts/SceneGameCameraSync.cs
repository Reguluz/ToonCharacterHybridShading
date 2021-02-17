using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class SceneGameCameraSync : MonoBehaviour 
{
	public bool SyncFOV;

	new Camera camera;

	void OnEnable()
	{
		camera = GetComponent<Camera>();
	}
	
#if UNITY_EDITOR
	void OnDrawGizmos () 
	{
		if (this.isActiveAndEnabled)
		{
			Camera sceneCam = ((UnityEditor.SceneView)UnityEditor.SceneView.sceneViews[0]).camera;
			camera.transform.position = sceneCam.transform.position;
			camera.transform.rotation = sceneCam.transform.rotation;
			if (SyncFOV) camera.fieldOfView = sceneCam.fieldOfView;
		}
	}
#endif
}
