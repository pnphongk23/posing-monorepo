# Tools and evidence

This is a task-oriented summary of the current upstream tool schema. Discover
the live schema again after upgrading Mobile MCP.

## Tool groups

| Purpose | Tools |
| --- | --- |
| Local device discovery | `mobile_list_available_devices` |
| App lifecycle | `mobile_list_apps`, `mobile_install_app`, `mobile_uninstall_app`, `mobile_launch_app`, `mobile_terminate_app` |
| Semantic inspection | `mobile_list_elements_on_screen`, `mobile_get_screen_size`, `mobile_get_orientation` |
| Interaction | `mobile_click_on_screen_at_coordinates`, `mobile_double_tap_on_screen`, `mobile_long_press_on_screen_at_coordinates`, `mobile_swipe_on_screen`, `mobile_type_keys`, `mobile_press_button`, `mobile_open_url`, `mobile_set_orientation` |
| Visual evidence | `mobile_take_screenshot`, `mobile_save_screenshot`, `mobile_start_screen_recording`, `mobile_stop_screen_recording` |
| Crash evidence | `mobile_list_crashes`, `mobile_get_crash` |
| Optional remote fleet | `mobile_login_to_cloud_provider`, `mobile_list_remote_devices`, `mobile_allocate_remote_device`, `mobile_release_remote_device` |

Every device-specific tool requires an explicit `device` identifier. Real-iOS
installation expects an `.ipa`; simulator installation accepts an `.app`
directory or `.zip` according to the upstream schema.

## Preferred interaction pattern

1. List devices and retain the exact selected ID in the test report.
2. Launch the bundle ID.
3. List current elements; select a control by label/identifier and calculate a
   point inside its current bounds.
4. Perform one action.
5. List elements again and assert the expected semantic state.
6. Capture a screenshot only for visual claims or failure diagnosis.

Do not reuse coordinates after navigation, orientation, keyboard, popup, or
permission changes. Coordinate-only success without a semantic or app-state
assertion is weak evidence.

## Camera evidence matrix

| Claim | Minimum evidence |
| --- | --- |
| Camera screen matches authority | Real-device screenshot plus explicit visual checklist and accessibility snapshot |
| Permission denied/recovery | Semantic state before and after denial; Settings transition evidence; capture remains disabled |
| Shutter duplicate protection | Recording or timed interaction; semantic disabled state; exactly one persisted record/file |
| Successful capture | Real iPhone; before/after thumbnail; readable file and matching database record |
| Flash/facing/zoom/grid/ratio applied | Real-device before/after evidence and captured-output comparison where applicable |
| Lifecycle interruption recovery | Recording/logs plus relaunch state, no stuck capture, no orphan file/record |
| No crash | Crash-list delta for the scenario, not merely continued UI responsiveness |

## Result template

```markdown
## Environment
- Mobile MCP version:
- Device / OS / device ID:
- App bundle ID / build:

## Scenarios
| Scenario | Result | Evidence | Notes |
| --- | --- | --- | --- |

## Blockers and limitations
- Blocked prerequisite and smallest next action.
```
