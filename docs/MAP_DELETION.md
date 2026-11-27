# Delete a custom map

In World Builder select the saved map in the dropdown, open the World settings tab, and click **Delete current map...**. Confirm to remove the map from the selector and return to Morrow Coast. Cancel leaves everything as-is.

Current unsaved edits are saved before removal, so the recovery copy includes them. If saving fails the map stays open. Deleted maps are moved to a unique folder under the writable map library's `deleted-maps` directory; the notice shows the recovery path. To recover, close the editor, copy the desired `.world.json` back into the map library (choose a new filename if it already exists), then reopen the editor. Existing automatic backups and published archives are retained.

Morrow Coast itself and the currently published PLAY map source cannot be deleted. The local editable copies of bundled presets can be deleted; opening the preset again creates a fresh copy without changing the bundled resource. No career saves or project assets are deleted.
