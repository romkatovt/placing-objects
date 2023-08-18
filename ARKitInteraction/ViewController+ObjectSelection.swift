/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Methods on the main view controller for handling virtual object loading and movement
*/

import UIKit
import ARKit

extension ViewController: VirtualObjectSelectionViewControllerDelegate {
    
    /** Adds the specified virtual object to the scene, placed at the world-space position
     estimated by a hit test from the center of the screen.
     - Tag: PlaceVirtualObject */
    func placeVirtualObject(_ virtualObject: VirtualObject) {
        guard focusSquare.state != .initializing, let query = virtualObject.raycastQuery else {
            self.statusViewController.showMessage("CANNOT PLACE OBJECT\nTry moving left or right.")
            if let controller = self.objectsViewController {
                self.virtualObjectSelectionViewController(controller, didDeselectObject: virtualObject)
            }
            return
        }
       
        let trackedRaycast = createTrackedRaycastAndSet3DPosition(of: virtualObject, from: query,
                                                                  withInitialResult: virtualObject.mostRecentInitialPlacementResult)
        
        virtualObject.raycast = trackedRaycast
        virtualObjectInteraction.selectedObject = virtualObject
        virtualObject.isHidden = false
    }
    
    // - Tag: GetTrackedRaycast
    func createTrackedRaycastAndSet3DPosition(of virtualObject: VirtualObject, from query: ARRaycastQuery,
                                              withInitialResult initialResult: ARRaycastResult? = nil) -> ARTrackedRaycast? {
        if let initialResult = initialResult {
            self.setTransform(of: virtualObject, with: initialResult)
        }
        
        return session.trackedRaycast(query) { (results) in
            self.setVirtualObject3DPosition(results, with: virtualObject)
        }
    }
    
    func createRaycastAndUpdate3DPosition(of virtualObject: VirtualObject, from query: ARRaycastQuery) {
        guard let result = session.raycast(query).first else {
            return
        }
        
        if virtualObject.allowedAlignment == .any && self.virtualObjectInteraction.trackedObject == virtualObject {
            
            // If an object that's aligned to a surface is being dragged, then
            // smoothen its orientation to avoid visible jumps, and apply only the translation directly.
            virtualObject.simdWorldPosition = result.worldTransform.translation
            
            let previousOrientation = virtualObject.simdWorldTransform.orientation
            let currentOrientation = result.worldTransform.orientation
            virtualObject.simdWorldOrientation = simd_slerp(previousOrientation, currentOrientation, 0.1)
        } else {
            self.setTransform(of: virtualObject, with: result)
        }
    }
    
    // - Tag: ProcessRaycastResults
    private func setVirtualObject3DPosition(_ results: [ARRaycastResult], with virtualObject: VirtualObject) {
        
        guard let result = results.first else {
            fatalError("Unexpected case: the update handler is always supposed to return at least one result.")
        }
        
        self.setTransform(of: virtualObject, with: result)
        
        // If the virtual object is not yet in the scene, add it.
        if virtualObject.parent == nil {
            self.sceneView.scene.rootNode.addChildNode(virtualObject)
            virtualObject.shouldUpdateAnchor = true
        }
        
        if virtualObject.shouldUpdateAnchor {
            virtualObject.shouldUpdateAnchor = false
            self.updateQueue.async {
                self.sceneView.addOrUpdateAnchor(for: virtualObject)
            }
        }
    }
    
    func setTransform(of virtualObject: VirtualObject, with result: ARRaycastResult) {
        virtualObject.simdWorldTransform = result.worldTransform
    }

    // MARK: - VirtualObjectSelectionViewControllerDelegate
    // - Tag: PlaceVirtualContent
    func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didSelectObject object: VirtualObject) {
        
    }
    
    func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didDeselectObject object: VirtualObject) {
        guard let objectIndex = virtualObjectLoader.loadedObjects.firstIndex(of: object) else {
            fatalError("Programmer error: Failed to lookup virtual object in scene.")
        }
        virtualObjectLoader.removeVirtualObject(at: objectIndex)
        virtualObjectInteraction.selectedObject = nil
        if let anchor = object.anchor {
            session.remove(anchor: anchor)
        }
    }

    // MARK: Object Loading UI

    func displayObjectLoadingUI() {
        // Show progress indicator.
        spinner.startAnimating()
        
        isRestartAvailable = false
    }

    func hideObjectLoadingUI() {
        // Hide progress indicator.
        spinner.stopAnimating()

        isRestartAvailable = true
    }
    
    func updateObjectAvailability() {
        guard let sceneView = sceneView else { return }
        
        // Update object availability only if the last update was at least half a second ago.
        if let lastUpdateTimestamp = lastObjectAvailabilityUpdateTimestamp,
            let timestamp = sceneView.session.currentFrame?.timestamp,
            timestamp - lastUpdateTimestamp < 0.5 {
            return
        } else {
            lastObjectAvailabilityUpdateTimestamp = sceneView.session.currentFrame?.timestamp
        }
                
        var newEnabledVirtualObjectRows = Set<Int>()
        for (row, object) in VirtualObject.availableObjects.enumerated() {
            // Enable row always if item is already placed, in order to allow the user to remove it.

            // Enable row if item can be placed at the current location
            if let query = sceneView.getRaycastQuery(for: object.allowedAlignment),
                let result = sceneView.castRay(for: query).first {
                object.mostRecentInitialPlacementResult = result
                object.raycastQuery = query
                newEnabledVirtualObjectRows.insert(row)
            } else {
                object.mostRecentInitialPlacementResult = nil
                object.raycastQuery = nil
            }
        }
    }
}
