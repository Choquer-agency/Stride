# Goal Persistence Testing Guide

This document provides comprehensive testing instructions to verify that the goal persistence fixes are working correctly.

## Overview of Changes

The following improvements have been implemented to fix goal persistence:

1. **Lifecycle Reload**: Goal is automatically reloaded when app returns to foreground
2. **Enhanced Error Handling**: Detailed logging for all goal storage operations
3. **Storage Validation**: Diagnostic checks on app startup to detect corrupted state
4. **Defensive Loading**: GoalManager attempts to self-heal corrupted storage

## Test Scenarios

### ✅ Test 1: Basic Goal Persistence (Happy Path)

**Objective**: Verify goal persists through normal app lifecycle

**Steps**:
1. Launch the app
2. Navigate to the Activity tab or Settings
3. Create a new goal:
   - Type: Race Goal
   - Distance: Half Marathon
   - Date: 3 months from now
   - Target Time: 1:45:00
   - Title: "Test Goal"
4. Verify the goal appears in the Activity tab
5. Close the app completely (swipe up from app switcher)
6. Wait 5 seconds
7. Reopen the app

**Expected Result**: 
- Goal should still be visible in Activity tab
- Console should show: `📌 Successfully loaded active goal: Test Goal`
- Settings should show the active goal

**Console Logs to Look For**:
```
📱 App became active
📌 Loading active goal from storage...
📁 Loaded active goal ID: [UUID]
📁 Loaded goal: Test Goal (ID: [UUID])
📌 Successfully loaded active goal: Test Goal
✅ Goal storage is healthy (active goal found)
```

---

### ✅ Test 2: Background/Foreground Transition

**Objective**: Verify goal persists when app is backgrounded and returned to foreground

**Steps**:
1. Launch the app with an existing goal
2. Verify goal is visible in Activity tab
3. Press home button to background the app (don't close it)
4. Wait 5 seconds
5. Return to the app

**Expected Result**:
- Goal should still be visible immediately
- Console should show goal was reloaded: `📌 Loading active goal from storage...`

---

### ✅ Test 3: Tab Navigation

**Objective**: Verify goal remains visible when switching between tabs

**Steps**:
1. Create a goal in Activity tab
2. Switch to Run tab
3. Switch to Plan tab
4. Switch to Settings tab
5. Return to Activity tab

**Expected Result**:
- Goal should remain visible in Activity and Settings tabs throughout navigation
- No "Set Goal" CTA should appear unless no goal exists

---

### ✅ Test 4: Goal Edit Persistence

**Objective**: Verify goal edits are saved and persist

**Steps**:
1. Create a goal
2. Navigate to Settings → Goal section
3. Tap on the active goal to edit
4. Change the title to "Updated Test Goal"
5. Change the target time
6. Save the changes
7. Close and reopen the app

**Expected Result**:
- Updated goal information should be visible
- Console should show: `🎯 Updated goal: Updated Test Goal`

---

### ⚠️ Test 5: Storage Corruption Recovery

**Objective**: Verify app handles corrupted goal ID gracefully

**Steps**:
1. Create a goal and verify it's visible
2. Close the app completely
3. Using Xcode or simulator file browser, navigate to:
   - Library/Application Support/[Your App]/Documents/
4. Open `active_goal_id.json` and replace content with invalid data: `"invalid-uuid-string"`
5. Reopen the app

**Expected Result**:
- App should not crash
- Console should show: `⚠️ Invalid UUID string in active_goal_id.json: invalid-uuid-string`
- Activity tab should show "Set Goal" CTA (no goal)
- No errors or crashes

**Console Logs to Look For**:
```
📁 Active goal ID file does not exist: [path] OR
⚠️ Invalid UUID string in active_goal_id.json: invalid-uuid-string
📌 No active goal ID found in storage
```

---

### ⚠️ Test 6: Missing Goal Data Recovery

**Objective**: Verify app handles case where active goal ID exists but goal data is missing

**Steps**:
1. Create a goal and verify it's visible
2. Close the app completely
3. Using Xcode or simulator file browser:
   - Keep `active_goal_id.json` intact
   - Delete or corrupt `goals.json`
4. Reopen the app

**Expected Result**:
- App should not crash
- Console should show: `⚠️ Active goal ID exists but goal data not found - storage may be corrupted`
- Activity tab should show "Set Goal" CTA
- App attempts to clear corrupted state

**Console Logs to Look For**:
```
📁 Goals file does not exist: [path]
📁 Loaded 0 goal(s) from storage
⚠️ Goal not found with ID: [UUID]. Total goals in storage: 0
⚠️ Active goal ID exists but goal data not found - storage may be corrupted
✅ Cleared active goal
```

---

### ✅ Test 7: Plan Generation Integration

**Objective**: Verify goal persists after generating a training plan

**Steps**:
1. Create a goal
2. Navigate to Plan tab
3. Configure preferences and generate a training plan
4. Wait for plan generation to complete
5. Navigate back to Activity tab
6. Close and reopen the app

**Expected Result**:
- Goal should remain visible throughout plan generation
- Goal should persist after app restart
- Plan should be linked to the goal (goalId matches)

---

### ✅ Test 8: Goal Deletion

**Objective**: Verify goal is properly removed when deleted

**Steps**:
1. Create a goal
2. Navigate to Settings → Goal section
3. Tap "Deactivate Goal"
4. Confirm deletion
5. Verify Activity tab shows "Set Goal" CTA
6. Close and reopen the app

**Expected Result**:
- Activity tab shows "Set Goal" CTA after deletion
- Console shows: `🎯 Deactivated goal` or `🎯 Deleted goal: [name]`
- After app restart, no goal should be loaded

---

### ✅ Test 9: Multiple App Restarts

**Objective**: Verify goal persists through multiple app launches

**Steps**:
1. Create a goal
2. Close app and reopen (1st restart)
3. Verify goal is visible
4. Close app and reopen (2nd restart)
5. Verify goal is visible
6. Close app and reopen (3rd restart)
7. Verify goal is visible

**Expected Result**:
- Goal should persist through all restarts
- Each restart should show successful goal loading in console

---

### ⚠️ Test 10: Storage Health Validation

**Objective**: Verify storage validation catches issues on startup

**Steps**:
1. Launch app with fresh install (no goals)
2. Check console for validation message
3. Create a goal
4. Close and reopen app
5. Check console for validation message

**Expected Result**:
- First launch: `✅ Goal storage is healthy (no active goal)`
- After creating goal: `✅ Goal storage is healthy (active goal found)`
- If issues detected: `⚠️ Issues: [description]`

---

## Console Output Reference

### Successful Goal Loading
```
📱 App became active
📌 Loading active goal from storage...
📁 Active goal ID file does not exist: [path]
OR
📁 Loaded active goal ID: [UUID]
📁 Loaded 1 goal(s) from storage
📁 Loaded goal: [Goal Name] (ID: [UUID])
📌 Successfully loaded active goal: [Goal Name]
✅ Goal storage is healthy (active goal found)
```

### No Active Goal (Normal)
```
📌 Loading active goal from storage...
📁 Active goal ID file does not exist: [path]
📌 No active goal ID found in storage
✅ Goal storage is healthy (no active goal)
```

### Storage Corruption Detected
```
📌 Loading active goal from storage...
📁 Loaded active goal ID: [UUID]
📁 Goals file does not exist: [path]
OR
❌ Goals file is corrupted: [details]
📁 Loaded 0 goal(s) from storage
⚠️ Goal not found with ID: [UUID]. Total goals in storage: 0
⚠️ Active goal ID exists but goal data not found - storage may be corrupted
✅ Cleared active goal
```

## Success Criteria

All tests should pass with the following outcomes:

✅ Goal persists through app restarts  
✅ Goal persists through background/foreground transitions  
✅ Goal persists through tab navigation  
✅ Goal edits are saved and persist  
✅ App gracefully handles storage corruption  
✅ App self-heals from corrupted state  
✅ Detailed error logging helps diagnose issues  
✅ Storage validation runs on app startup  
✅ User never loses goal unless explicitly deleted  

## Troubleshooting

If a test fails, check the console for:

1. **Missing log statements**: Indicates function wasn't called
2. **Error messages**: Shows what went wrong
3. **UUID mismatches**: Indicates ID and data are out of sync
4. **File path issues**: Shows if storage location is incorrect

## Automated Testing (Future)

For automated testing, consider adding unit tests for:

- `GoalManager.loadActiveGoal()` with various storage states
- `StorageManager.loadActiveGoalId()` with corrupted data
- `StorageManager.validateGoalStorage()` with different scenarios
- Goal persistence through mock lifecycle events

---

**Last Updated**: January 24, 2026  
**Related Fix**: Goal Persistence Implementation
