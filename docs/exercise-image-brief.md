# STRIDE — Exercise Guide Image Brief

You are generating instructional photo sequences for a running app's guided gym player. Each exercise gets 2–3 images showing the key positions of the movement, displayed in-app as a small horizontal strip above the "Done" button — so clarity at thumbnail size matters more than artistry.

## Global style — apply to EVERY image, never deviate

- **Photorealistic.** One consistent athlete in every single image: male, early 30s, average athletic build, short brown hair, plain heather-gray t-shirt, black shorts, gray running shoes. Same person, same outfit, all images.
- **Setting:** clean, minimal home gym — light gray walls, black rubber floor mats, soft even daylight. No clutter, no mirrors, no gym branding. The only equipment visible is what the exercise uses.
- **Equipment (match exactly — this is the user's actual gym):** black barbell with red-and-black kg bumper plates on a black squat rack; adjustable dumbbells (black, hex-style); flat black bench; wall-mounted pull-up bar; landmine attachment (barbell anchored in a floor sleeve); black plyo box; rubber medicine ball.
- **Framing:** full body always in frame, camera at chest height, shot from the angle that makes the form clearest (specified per exercise). Square 1:1, at least 1024×1024.
- **No text, no arrows, no watermarks, no split panels.** One position per image.
- **Consistency trick:** generate the first image (Back Squat step 1), then reference it for every subsequent generation ("same athlete, same gym, same lighting as previous"). If the tool supports seeds or reference images, lock them.

## Output

Save each image as PNG into the repo at `StrideApp/ExerciseImages/` using the exact filename given, e.g. `back_squat_1.png`. Do not rename or add suffixes — the app will load these by name.

---

## 1. Back Squat — `back_squat_1/2/3`
Side view (90°), barbell + squat rack.
1. Athlete standing tall inside the rack, barbell resting across upper back/traps, hands gripping just outside shoulders, feet shoulder-width, chest up.
2. Bottom of the squat: hips back and down until thighs are parallel to the floor, knees tracking over toes, heels flat, chest up, back neutral.
3. Standing fully upright again, bar still on back — glutes squeezed, knees locked out.

## 2. Barbell RDL (Romanian Deadlift) — `barbell_rdl_1/2`
Side view, barbell only (no rack).
1. Standing tall holding the barbell at thigh height, overhand grip, feet hip-width, soft bend in the knees, shoulders back.
2. Hinged at the hips: bar slid down to just below the knees, back perfectly flat, hips pushed far behind, slight knee bend unchanged, hamstrings visibly stretched, gaze down-forward.

## 3. Goblet Squat — `goblet_squat_1/2`
Front three-quarter view, one dumbbell.
1. Standing, holding a single dumbbell vertically against the chest with both hands cupped under the top head, elbows tucked, feet slightly wider than shoulders.
2. Bottom of the squat: elbows brushing inside the knees, thighs parallel, torso upright, dumbbell still tight to chest.

## 4. DB Bulgarian Split Squat — `bulgarian_split_squat_1/2`
Side view, bench + two dumbbells.
1. Standing lunge stance in front of the bench, rear foot laces-down on the bench behind, dumbbell in each hand at sides, torso tall.
2. Bottom position: front thigh parallel to floor, rear knee dropped toward the floor, front knee over mid-foot, torso upright, dumbbells hanging vertically.

## 5. DB Split Squat — `db_split_squat_1/2`
Side view, two dumbbells, both feet on the floor.
1. Static lunge stance — one foot forward, one back with heel raised, dumbbells at sides, torso tall.
2. Bottom: both knees at ~90°, rear knee hovering just above the floor, front shin vertical, dumbbells at sides.

## 6. DB Box Step-Up — `box_step_up_1/2/3`
Side three-quarter view, plyo box + two dumbbells.
1. Standing facing the box, one full foot planted flat on top of it, dumbbells at sides.
2. Mid-drive: pushing through the top foot, body rising, trailing leg leaving the floor — top leg doing all the work.
3. Standing fully on top of the box, both feet, tall posture, dumbbells at sides.

## 7. Single-Leg Glute Bridge — `single_leg_glute_bridge_1/2`
Side view, floor mat only.
1. Lying on back, one knee bent with foot flat on the floor, the other leg extended straight and raised, arms flat at sides.
2. Hips driven up into a bridge: straight line from shoulder through hip to bent knee, extended leg held in line with the torso, glute squeezed.

## 8. Single-Leg Calf Raise — `single_leg_calf_raise_1/2`
Side view, standing on the edge of the plyo box or a step, fingertips on the rack for balance.
1. Standing on one foot, ball of the foot on the edge, heel dropped below the step level — deep calf stretch, other foot hooked behind the ankle.
2. Risen up onto the toes of that one foot as high as possible, heel well above the step.

## 9. Single-Leg Balance Reach — `single_leg_balance_reach_1/2`
Front three-quarter view, no equipment.
1. Standing balanced on one leg, other knee slightly lifted, arms relaxed, tall posture.
2. Hinged forward reaching both hands toward the floor in front while the free leg extends straight behind — a controlled single-leg hinge, back flat, standing knee softly bent.

## 10. Pull-Ups — `pull_ups_1/2`
Front view, wall-mounted pull-up bar.
1. Dead hang: arms fully extended, overhand grip just outside shoulders, feet crossed behind, shoulders active (not shrugged into the ears).
2. Top position: chin clearly above the bar, elbows driven down and back, chest toward the bar.

## 11. Landmine Press — `landmine_press_1/2`
Side three-quarter view, landmine (barbell anchored to the floor sleeve, plate on the top end).
1. Half-kneeling (one knee down), holding the loaded end of the barbell at the shoulder with one hand, elbow bent, torso tall and braced.
2. Arm pressed to full extension up-and-forward along the bar's arc, shoulder blade reaching, torso still vertical.

## 12. Landmine Rotation — `landmine_rotation_1/2/3`
Front view, landmine, standing.
1. Standing with feet wide, holding the end of the barbell with both arms extended straight up in front of the chest.
2. Arms sweeping the bar down toward one hip, hips and torso rotating with it, arms staying long.
3. Same position mirrored to the other hip — showing the full arc travels side to side.

## 13. Med Ball Rotational Chest Pass — `med_ball_rotational_pass_1/2/3`
Side-on to a bare wall, rubber medicine ball. IMPORTANT: ball stays at chest height throughout — nothing overhead.
1. Athlete side-on to the wall, ball held at the chest, hips coiled away from the wall, weight loaded on the back leg.
2. Mid-throw: hips snapping toward the wall, arms extending, ball just leaving the hands at chest height toward the wall.
3. Follow-through facing the wall, arms extended, rear heel pivoted, ball in flight at chest height.

## 14. Suitcase Carry — `suitcase_carry_1/2`
Front view, one dumbbell.
1. Standing tall holding a single heavy dumbbell in one hand at the side — like a suitcase — shoulders dead level, no lean toward the weight, other arm relaxed.
2. Mid-stride walking, dumbbell still at the side, torso perfectly upright and level — the whole point is resisting the sideways pull.

## 15. Plank — `plank_1`
Side view, floor mat. One image is enough.
1. Forearm plank: elbows under shoulders, body one straight line from head to heels, glutes and core braced, no sagging hips, neutral neck.

## 16. Side Plank — `side_plank_1`
Front-on view, floor mat. One image.
1. Side plank on one forearm: elbow under shoulder, feet stacked, hips lifted so the body forms a straight diagonal line, top arm resting on hip.

## 17. Side Plank with Hip Abduction — `side_plank_abduction_1/2`
Front-on view, floor mat.
1. Side plank position, hips high, feet stacked.
2. Same plank with the top leg lifted 30–40 cm above the bottom leg, held straight — hips still high, no rolling back.

## 18. Copenhagen Plank on Bench — `copenhagen_plank_1`
Front-on view, flat bench. One image.
1. Side plank with the TOP leg's inner foot/ankle resting on the bench, bottom leg held straight underneath it off the floor, forearm under shoulder, body straight — inner thigh of the top leg doing the work.

## 19. Dead Bug — `dead_bug_1/2`
Overhead three-quarter view, floor mat.
1. Lying on back: both arms pointing straight up at the ceiling, hips and knees at 90° (shins parallel to floor), lower back pressed flat.
2. Opposite arm and opposite leg extended long and low toward the floor (arm overhead, leg straight, both hovering) while the other arm/leg hold position — lower back still flat.

## 20. Bird Dog — `bird_dog_1/2`
Side view, floor mat.
1. All-fours: hands under shoulders, knees under hips, back flat like a table.
2. Opposite arm and opposite leg extended fully — arm straight ahead, leg straight behind, both parallel to the floor, hips square, no arching.

## 21. Clamshells — `clamshells_1/2`
Front three-quarter view, floor mat.
1. Lying on one side, knees bent ~90° and stacked, feet together, head resting on the lower arm.
2. Top knee rotated open toward the ceiling like a clamshell opening — feet still touching, pelvis stacked and NOT rolling backward.

## 22. Hip Flexor Stretch — `hip_flexor_stretch_1`
Side view, floor mat. One image.
1. Half-kneeling: rear knee on the mat, front foot planted with knee at 90°, hips pressed gently forward, torso tall, rear-side glute squeezed — visible stretch through the front of the rear hip. Same-side arm reaching straight overhead.
