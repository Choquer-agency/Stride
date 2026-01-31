import Foundation

/// Singleton library of runner-focused exercises
class ExerciseLibrary {
    static let shared = ExerciseLibrary()
    
    private(set) var allExercises: [Exercise] = []
    private var exercisesBySlug: [String: Exercise] = [:]
    
    private init() {
        loadExercises()
        validateLibrary()
    }
    
    // MARK: - Library Loading
    
    private func loadExercises() {
        allExercises = [
            // MARK: - Strength Exercises (15)
            
            // Squat variations
            Exercise(
                slug: "bulgarian_split_squat",
                name: "Bulgarian Split Squat",
                category: .strength,
                primaryMuscles: [.quads, .glutes],
                secondaryMuscles: [.hamstrings],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.knee],
                defaultSets: 3,
                defaultReps: 8...12,
                defaultRestSeconds: 90,
                loadType: .fixedRecommendation,
                loadGuidance: "Use a weight you could lift 10-12 times with good form",
                whyItHelpsRunners: "Builds single-leg strength and balance critical for running efficiency. Strengthens glutes and quads to reduce knee stress during push-off.",
                commonMistakes: ["Letting front knee collapse inward", "Leaning too far forward", "Not going deep enough"],
                coachingCues: ["Keep front knee tracking over toes", "Drive through front heel", "Chest up, core braced"],
                requiredEquipment: [.dumbbells],
                alternativeExercises: ["reverse_lunge", "single_leg_squat", "step_up"],
                movementPattern: .lunge
            ),
            
            Exercise(
                slug: "goblet_squat",
                name: "Goblet Squat",
                category: .strength,
                primaryMuscles: [.quads, .glutes],
                secondaryMuscles: [.core],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                defaultSets: 3,
                defaultReps: 10...15,
                defaultRestSeconds: 75,
                loadType: .fixedRecommendation,
                loadGuidance: "Use a moderate weight that allows full depth squats",
                whyItHelpsRunners: "Develops lower body power while reinforcing proper squat mechanics. Strengthens quads and glutes for hill climbing and acceleration.",
                commonMistakes: ["Knees caving in", "Heels lifting", "Not reaching full depth"],
                coachingCues: ["Hold weight at chest", "Push knees out", "Keep weight in heels"],
                requiredEquipment: [.dumbbells],
                alternativeExercises: ["bodyweight_squat", "single_leg_squat", "box_squat"],
                movementPattern: .squat
            ),
            
            Exercise(
                slug: "single_leg_squat",
                name: "Single-Leg Squat (Pistol)",
                category: .strength,
                primaryMuscles: [.quads, .glutes],
                secondaryMuscles: [.core, .hips],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .general],
                injuryPreventionTags: [.knee],
                defaultSets: 3,
                defaultReps: 5...10,
                defaultRestSeconds: 90,
                loadType: .bodyweight,
                loadGuidance: "Use assistance (TRX or pole) if needed, progress to full pistol",
                whyItHelpsRunners: "Ultimate single-leg strength builder. Develops the balance and control needed for stable, efficient running form.",
                commonMistakes: ["Knee collapsing inward", "Losing balance backwards", "Not controlling descent"],
                coachingCues: ["Keep standing knee aligned", "Sit back into heel", "Control the movement"],
                requiredEquipment: [.none],
                alternativeExercises: ["bulgarian_split_squat", "goblet_squat"],
                movementPattern: .squat
            ),
            
            // Hinge variations
            Exercise(
                slug: "single_leg_rdl",
                name: "Single-Leg Romanian Deadlift",
                category: .strength,
                primaryMuscles: [.hamstrings, .glutes],
                secondaryMuscles: [.core],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hamstring, .knee],
                defaultSets: 3,
                defaultReps: 8...12,
                defaultRestSeconds: 75,
                loadType: .fixedRecommendation,
                loadGuidance: "Start light to master balance, then progress weight",
                whyItHelpsRunners: "Strengthens hamstrings eccentrically, critical for injury prevention. Develops posterior chain strength for powerful push-off and uphill running.",
                commonMistakes: ["Rounding lower back", "Bending knee too much", "Losing balance"],
                coachingCues: ["Hinge at hips, not spine", "Keep back flat", "Drive heel into ground"],
                requiredEquipment: [.dumbbells],
                alternativeExercises: ["nordic_curl", "glute_bridge", "landmine_single_leg_rdl"],
                movementPattern: .hinge,
                avoidIf: [.hamstring]
            ),
            
            Exercise(
                slug: "hip_thrust",
                name: "Hip Thrust",
                category: .strength,
                primaryMuscles: [.glutes],
                secondaryMuscles: [.hamstrings],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.knee, .hip],
                defaultSets: 3,
                defaultReps: 10...15,
                defaultRestSeconds: 75,
                loadType: .fixedRecommendation,
                loadGuidance: "Use moderate weight, focus on glute contraction at top",
                whyItHelpsRunners: "The best glute-building exercise for runners. Strong glutes drive powerful propulsion and reduce knee and IT band stress.",
                commonMistakes: ["Overarching lower back", "Not fully extending hips", "Using momentum"],
                coachingCues: ["Drive through heels", "Squeeze glutes at top", "Control the descent"],
                requiredEquipment: [.bench, .barbell],
                alternativeExercises: ["glute_bridge", "single_leg_glute_bridge"],
                movementPattern: .hinge
            ),
            
            Exercise(
                slug: "glute_bridge",
                name: "Glute Bridge",
                category: .strength,
                primaryMuscles: [.glutes],
                secondaryMuscles: [.hamstrings, .core],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hip, .knee],
                defaultSets: 3,
                defaultReps: 12...15,
                defaultRestSeconds: 60,
                loadType: .bodyweight,
                loadGuidance: "Bodyweight to start, can add weight plate on hips",
                whyItHelpsRunners: "Activates and strengthens glutes, essential for preventing 'dead butt syndrome' in distance runners. Improves hip extension power.",
                commonMistakes: ["Pushing through toes instead of heels", "Overarching back", "Not squeezing glutes"],
                coachingCues: ["Drive through heels", "Squeeze glutes hard at top", "Hold for 2 seconds"],
                requiredEquipment: [.none],
                alternativeExercises: ["hip_thrust", "single_leg_glute_bridge"],
                movementPattern: .hinge
            ),
            
            Exercise(
                slug: "single_leg_glute_bridge",
                name: "Single-Leg Glute Bridge",
                category: .strength,
                primaryMuscles: [.glutes],
                secondaryMuscles: [.hamstrings, .core],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .general],
                injuryPreventionTags: [.hip, .knee],
                defaultSets: 3,
                defaultReps: 10...12,
                defaultRestSeconds: 60,
                loadType: .bodyweight,
                loadGuidance: "Master bilateral version first, then progress to single-leg",
                whyItHelpsRunners: "Builds unilateral glute strength and hip stability. Addresses left-right imbalances that can lead to injury.",
                commonMistakes: ["Hips rotating to side", "Not maintaining level pelvis", "Using momentum"],
                coachingCues: ["Keep hips level", "Drive through heel", "Control both up and down"],
                requiredEquipment: [.none],
                alternativeExercises: ["glute_bridge", "hip_thrust"],
                movementPattern: .hinge
            ),
            
            Exercise(
                slug: "nordic_curl",
                name: "Nordic Hamstring Curl",
                category: .strength,
                primaryMuscles: [.hamstrings],
                secondaryMuscles: [.glutes],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hamstring],
                defaultSets: 3,
                defaultReps: 4...8,
                defaultRestSeconds: 120,
                loadType: .bodyweight,
                loadGuidance: "Extremely challenging - use resistance band assistance if needed",
                whyItHelpsRunners: "The gold standard for hamstring injury prevention. Builds eccentric hamstring strength to withstand high-speed running forces.",
                commonMistakes: ["Collapsing too fast", "Breaking at hips instead of knees", "Not using full range"],
                coachingCues: ["Lower slowly", "Keep body straight", "Use hands to catch yourself"],
                requiredEquipment: [.none],
                alternativeExercises: ["single_leg_rdl", "stability_ball_hamstring_curl"],
                movementPattern: .hinge,
                avoidIf: [.hamstring]
            ),
            
            // Calf exercises
            Exercise(
                slug: "single_leg_calf_raise",
                name: "Single-Leg Calf Raise",
                category: .strength,
                primaryMuscles: [.calves],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.calf, .achilles],
                defaultSets: 3,
                defaultReps: 12...15,
                defaultRestSeconds: 45,
                loadType: .bodyweight,
                loadGuidance: "Control the eccentric - 3 seconds down",
                whyItHelpsRunners: "Builds calf strength and Achilles resilience. Strong calves improve push-off power and reduce injury risk during speedwork.",
                commonMistakes: ["Bouncing at bottom", "Not going through full range", "Rushing the movement"],
                coachingCues: ["Rise high on toes", "Lower slowly for 3 seconds", "Full range of motion"],
                requiredEquipment: [.none],
                alternativeExercises: ["double_leg_calf_raise", "seated_calf_raise"],
                movementPattern: .calf,
                avoidIf: [.achilles, .calf]
            ),
            
            Exercise(
                slug: "eccentric_calf_lower",
                name: "Eccentric Calf Lower",
                category: .prehab,
                primaryMuscles: [.calves],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.halfMarathon, .marathon, .general],
                injuryPreventionTags: [.achilles],
                defaultSets: 3,
                defaultReps: 10...12,
                defaultRestSeconds: 45,
                loadType: .bodyweight,
                loadGuidance: "5-second lowering phase, use both legs to raise",
                whyItHelpsRunners: "Specifically rehabilitates and strengthens the Achilles tendon. Essential for runners with Achilles sensitivity or high mileage.",
                commonMistakes: ["Lowering too fast", "Not going below platform level", "Not loading affected leg"],
                coachingCues: ["Lower over 5 seconds", "Go below parallel", "Feel stretch in Achilles"],
                requiredEquipment: [.none],
                alternativeExercises: ["single_leg_calf_raise"],
                movementPattern: .calf,
                avoidIf: []  // Actually therapeutic for Achilles
            ),
            
            // Lunge variations
            Exercise(
                slug: "reverse_lunge",
                name: "Reverse Lunge",
                category: .strength,
                primaryMuscles: [.quads, .glutes],
                secondaryMuscles: [.hamstrings],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                defaultSets: 3,
                defaultReps: 10...12,
                defaultRestSeconds: 75,
                loadType: .fixedRecommendation,
                loadGuidance: "Dumbbells at sides or goblet-style at chest",
                whyItHelpsRunners: "Builds single-leg strength with less knee stress than forward lunges. Mimics the running stance and strengthens the entire leg.",
                commonMistakes: ["Front knee caving in", "Short stepping", "Losing balance"],
                coachingCues: ["Step back and down", "Keep front shin vertical", "Drive through front heel"],
                requiredEquipment: [.dumbbells],
                alternativeExercises: ["bulgarian_split_squat", "walking_lunge"],
                movementPattern: .lunge
            ),
            
            Exercise(
                slug: "lateral_lunge",
                name: "Lateral Lunge",
                category: .strength,
                primaryMuscles: [.glutes, .hips],
                secondaryMuscles: [.quads],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .general],
                injuryPreventionTags: [.hip, .knee],
                defaultSets: 3,
                defaultReps: 8...10,
                defaultRestSeconds: 60,
                loadType: .fixedRecommendation,
                loadGuidance: "Start bodyweight, progress to goblet-style hold",
                whyItHelpsRunners: "Strengthens lateral hip stabilizers often neglected in forward-only running. Reduces IT band syndrome and improves balance on uneven terrain.",
                commonMistakes: ["Not sitting back into hip", "Knee collapsing inward", "Feet not staying flat"],
                coachingCues: ["Push hips back", "Keep chest up", "Both feet stay flat"],
                requiredEquipment: [.dumbbells],
                alternativeExercises: ["lateral_band_walk", "cossack_squat"],
                movementPattern: .lunge
            ),
            
            // Core
            Exercise(
                slug: "plank",
                name: "Front Plank",
                category: .stability,
                primaryMuscles: [.core],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                defaultSets: 3,
                defaultDurationSeconds: 45,
                defaultRestSeconds: 45,
                loadType: .bodyweight,
                loadGuidance: "Hold proper form - quality over duration",
                whyItHelpsRunners: "Builds core endurance to maintain running posture during fatigue. Strong core reduces energy waste and lower back pain.",
                commonMistakes: ["Hips sagging", "Shoulders shrugging up", "Holding breath"],
                coachingCues: ["Body straight as a board", "Squeeze glutes", "Breathe steadily"],
                requiredEquipment: [.none],
                alternativeExercises: ["dead_bug", "bird_dog", "stability_ball_plank"],
                movementPattern: .core
            ),
            
            Exercise(
                slug: "side_plank",
                name: "Side Plank",
                category: .stability,
                primaryMuscles: [.core, .hips],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hip, .knee],
                defaultSets: 3,
                defaultDurationSeconds: 30,
                defaultRestSeconds: 45,
                loadType: .bodyweight,
                loadGuidance: "Start on elbow, progress to straight arm",
                whyItHelpsRunners: "Strengthens lateral core and hip stabilizers. Essential for preventing hip drop during running, which leads to IT band issues.",
                commonMistakes: ["Hips dropping", "Rolling forward or back", "Not stacked properly"],
                coachingCues: ["Hips high", "Body in straight line", "Top arm to ceiling"],
                requiredEquipment: [.none],
                alternativeExercises: ["lateral_lunge", "clamshell"],
                movementPattern: .core
            ),
            
            Exercise(
                slug: "dead_bug",
                name: "Dead Bug",
                category: .stability,
                primaryMuscles: [.core],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                defaultSets: 3,
                defaultReps: 10...12,
                defaultRestSeconds: 45,
                loadType: .bodyweight,
                loadGuidance: "Move slowly and maintain lower back contact with floor",
                whyItHelpsRunners: "Teaches core stability while moving limbs independently - exactly what happens during running. Protects lower back and improves coordination.",
                commonMistakes: ["Lower back arching off floor", "Moving too fast", "Not breathing"],
                coachingCues: ["Press back into floor", "Move opposite limbs", "Exhale as you extend"],
                requiredEquipment: [.none],
                alternativeExercises: ["plank", "bird_dog"],
                movementPattern: .core
            ),
            
            // MARK: - Stability Exercises (8)
            
            Exercise(
                slug: "single_leg_balance",
                name: "Single-Leg Balance",
                category: .stability,
                primaryMuscles: [.hips, .calves],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.knee, .ankle, .hip],
                defaultSets: 3,
                defaultDurationSeconds: 30,
                defaultRestSeconds: 30,
                loadType: .bodyweight,
                loadGuidance: "Progress by closing eyes or standing on unstable surface",
                whyItHelpsRunners: "Develops proprioception and ankle stability. Reduces injury risk on uneven terrain and improves single-leg running stability.",
                commonMistakes: ["Shifting weight to outside of foot", "Not engaging core", "Holding breath"],
                coachingCues: ["Spread toes", "Engage core", "Focus on steady point"],
                requiredEquipment: [.none],
                alternativeExercises: ["single_leg_rdl", "single_leg_calf_raise"],
                movementPattern: .stability
            ),
            
            Exercise(
                slug: "lateral_band_walk",
                name: "Lateral Band Walk",
                category: .stability,
                primaryMuscles: [.hips, .glutes],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.knee, .hip],
                defaultSets: 3,
                defaultReps: 12...15,
                defaultRestSeconds: 45,
                loadType: .rpe,
                loadGuidance: "Use band tension that creates moderate burn",
                whyItHelpsRunners: "Activates and strengthens hip abductors to prevent knee collapse. Essential for runners prone to knee pain or IT band syndrome.",
                commonMistakes: ["Standing too upright", "Taking tiny steps", "Not maintaining tension"],
                coachingCues: ["Slight squat position", "Push knees out", "Keep tension constant"],
                requiredEquipment: [.resistanceBands],
                alternativeExercises: ["clamshell", "lateral_lunge"],
                movementPattern: .stability
            ),
            
            Exercise(
                slug: "clamshell",
                name: "Clamshell",
                category: .stability,
                primaryMuscles: [.hips, .glutes],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hip, .knee],
                defaultSets: 3,
                defaultReps: 15...20,
                defaultRestSeconds: 45,
                loadType: .rpe,
                loadGuidance: "Use band for resistance, focus on quality reps",
                whyItHelpsRunners: "Targets the gluteus medius, critical for hip stability during single-leg stance. Prevents hip drop and reduces knee stress.",
                commonMistakes: ["Rolling back", "Moving at waist instead of hip", "Using momentum"],
                coachingCues: ["Keep feet together", "Rotate at hip only", "Control the movement"],
                requiredEquipment: [.resistanceBands],
                alternativeExercises: ["lateral_band_walk", "side_plank"],
                movementPattern: .stability
            ),
            
            Exercise(
                slug: "bird_dog",
                name: "Bird Dog",
                category: .stability,
                primaryMuscles: [.core, .glutes],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                defaultSets: 3,
                defaultReps: 10...12,
                defaultRestSeconds: 45,
                loadType: .bodyweight,
                loadGuidance: "Move slowly, maintain neutral spine throughout",
                whyItHelpsRunners: "Develops core stability and coordination. Mimics the cross-body pattern of running while building anti-rotation strength.",
                commonMistakes: ["Rotating torso", "Rushing the movement", "Hyperextending back"],
                coachingCues: ["Reach long with arm and leg", "Don't rotate", "Keep hips level"],
                requiredEquipment: [.none],
                alternativeExercises: ["dead_bug", "plank"],
                movementPattern: .core
            ),
            
            Exercise(
                slug: "monster_walk",
                name: "Monster Walk",
                category: .stability,
                primaryMuscles: [.hips, .glutes],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.knee, .hip],
                defaultSets: 3,
                defaultReps: 10...12,
                defaultRestSeconds: 45,
                loadType: .rpe,
                loadGuidance: "Band above knees, moderate tension",
                whyItHelpsRunners: "Activates hip stabilizers in a functional forward movement pattern. Excellent warm-up or standalone strengthening exercise.",
                commonMistakes: ["Not maintaining squat", "Letting knees cave in", "Taking tiny steps"],
                coachingCues: ["Stay in quarter squat", "Push knees out", "Step forward and out"],
                requiredEquipment: [.resistanceBands],
                alternativeExercises: ["lateral_band_walk", "clamshell"],
                movementPattern: .stability
            ),
            
            Exercise(
                slug: "copenhagen_plank",
                name: "Copenhagen Plank",
                category: .stability,
                primaryMuscles: [.hips, .core],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .general],
                injuryPreventionTags: [.groin, .hip],
                defaultSets: 3,
                defaultDurationSeconds: 20,
                defaultRestSeconds: 60,
                loadType: .bodyweight,
                loadGuidance: "Very challenging - start with bottom knee on ground",
                whyItHelpsRunners: "The most effective adductor strengthening exercise. Prevents groin strains and improves hip stability during toe-off.",
                commonMistakes: ["Hips sagging", "Not engaging top leg", "Poor shoulder position"],
                coachingCues: ["Squeeze top leg up", "Keep body straight", "Engage everything"],
                requiredEquipment: [.bench],
                alternativeExercises: ["side_plank", "lateral_lunge"],
                movementPattern: .core
            ),
            
            Exercise(
                slug: "pallof_press",
                name: "Pallof Press",
                category: .stability,
                primaryMuscles: [.core],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                defaultSets: 3,
                defaultReps: 10...12,
                defaultRestSeconds: 45,
                loadType: .fixedRecommendation,
                loadGuidance: "Use resistance that allows controlled movement",
                whyItHelpsRunners: "Builds anti-rotation core strength. Helps maintain straight running form even when fatigued, improving efficiency.",
                commonMistakes: ["Allowing torso rotation", "Using arms only", "Not fully extending"],
                coachingCues: ["Stand perpendicular to anchor", "Press straight out", "Resist rotation"],
                requiredEquipment: [.resistanceBands, .cableMachine],
                alternativeExercises: ["plank", "dead_bug"],
                movementPattern: .core
            ),
            
            Exercise(
                slug: "stability_ball_hamstring_curl",
                name: "Stability Ball Hamstring Curl",
                category: .stability,
                primaryMuscles: [.hamstrings, .glutes],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hamstring],
                defaultSets: 3,
                defaultReps: 10...12,
                defaultRestSeconds: 60,
                loadType: .bodyweight,
                loadGuidance: "Control the ball, don't let it roll away",
                whyItHelpsRunners: "Builds hamstring strength in an unstable environment, improving dynamic stability. Also works glutes and core simultaneously.",
                commonMistakes: ["Hips sagging", "Moving too fast", "Not using full range"],
                coachingCues: ["Hips up throughout", "Pull with heels", "Control both directions"],
                requiredEquipment: [.medicineBall],
                alternativeExercises: ["nordic_curl", "single_leg_rdl"],
                movementPattern: .hinge,
                avoidIf: [.hamstring]
            ),
            
            // MARK: - Mobility Exercises (8)
            
            Exercise(
                slug: "leg_swings_forward",
                name: "Leg Swings (Forward/Back)",
                category: .mobility,
                primaryMuscles: [.hips, .hamstrings],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                defaultSets: 2,
                defaultReps: 10...15,
                defaultRestSeconds: 30,
                loadType: .bodyweight,
                loadGuidance: "Controlled swings, gradually increasing range",
                whyItHelpsRunners: "Dynamically warms up hip flexors and hamstrings. Prepares the running range of motion and activates key muscles.",
                commonMistakes: ["Swinging too aggressively", "Arching back", "Not staying tall"],
                coachingCues: ["Stay tall", "Control the swing", "Increase range gradually"],
                requiredEquipment: [.none],
                alternativeExercises: ["walking_leg_cradle", "hip_circles"],
                movementPattern: .mobility
            ),
            
            Exercise(
                slug: "leg_swings_lateral",
                name: "Leg Swings (Side to Side)",
                category: .mobility,
                primaryMuscles: [.hips],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hip],
                defaultSets: 2,
                defaultReps: 10...15,
                defaultRestSeconds: 30,
                loadType: .bodyweight,
                loadGuidance: "Swing across body and out to side",
                whyItHelpsRunners: "Opens up lateral hip mobility often restricted in runners. Reduces IT band tightness and improves hip range of motion.",
                commonMistakes: ["Rotating torso", "Too much momentum", "Not staying balanced"],
                coachingCues: ["Keep torso still", "Cross midline", "Stay balanced"],
                requiredEquipment: [.none],
                alternativeExercises: ["hip_circles", "walking_leg_cradle"],
                movementPattern: .mobility
            ),
            
            Exercise(
                slug: "world_greatest_stretch",
                name: "World's Greatest Stretch",
                category: .mobility,
                primaryMuscles: [.hips, .hamstrings, .core],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                defaultSets: 2,
                defaultReps: 5...6,
                defaultRestSeconds: 30,
                loadType: .bodyweight,
                loadGuidance: "Move through each position deliberately",
                whyItHelpsRunners: "The ultimate full-body mobility move for runners. Opens hips, stretches hamstrings, and rotates thoracic spine all in one.",
                commonMistakes: ["Rushing through positions", "Not rotating fully", "Losing balance"],
                coachingCues: ["Hold each position 2 seconds", "Reach elbow to ground", "Rotate to sky"],
                requiredEquipment: [.none],
                alternativeExercises: ["walking_lunge_with_twist", "spiderman_stretch"],
                movementPattern: .mobility
            ),
            
            Exercise(
                slug: "hip_circles",
                name: "Hip Circles",
                category: .mobility,
                primaryMuscles: [.hips],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hip],
                defaultSets: 2,
                defaultReps: 10...12,
                defaultRestSeconds: 30,
                loadType: .bodyweight,
                loadGuidance: "Large, controlled circles in both directions",
                whyItHelpsRunners: "Lubricates hip joint and improves range of motion in all planes. Excellent for runners with tight hips or hip flexor issues.",
                commonMistakes: ["Circles too small", "Not staying balanced", "Moving too fast"],
                coachingCues: ["Big circles", "Both directions", "Stay tall"],
                requiredEquipment: [.none],
                alternativeExercises: ["leg_swings_lateral", "walking_leg_cradle"],
                movementPattern: .mobility
            ),
            
            Exercise(
                slug: "ankle_mobility_drill",
                name: "Ankle Mobility Drill",
                category: .mobility,
                primaryMuscles: [.calves],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.ankle, .calf, .achilles],
                defaultSets: 2,
                defaultReps: 10...12,
                defaultRestSeconds: 30,
                loadType: .bodyweight,
                loadGuidance: "Drive knee forward over toes without heel lifting",
                whyItHelpsRunners: "Improves ankle dorsiflexion, critical for efficient foot strike and push-off. Reduces calf and Achilles strain.",
                commonMistakes: ["Heel lifting", "Not driving knee forward", "Moving too fast"],
                coachingCues: ["Heel stays down", "Drive knee past toes", "Feel stretch in calf"],
                requiredEquipment: [.none],
                alternativeExercises: ["calf_stretch", "toe_walks"],
                movementPattern: .mobility
            ),
            
            Exercise(
                slug: "thoracic_rotation",
                name: "Thoracic Rotation",
                category: .mobility,
                primaryMuscles: [.core],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                defaultSets: 2,
                defaultReps: 8...10,
                defaultRestSeconds: 30,
                loadType: .bodyweight,
                loadGuidance: "Rotate from mid-back, not lower back",
                whyItHelpsRunners: "Improves upper body rotation for efficient arm swing. Reduces neck and shoulder tension during long runs.",
                commonMistakes: ["Rotating from hips", "Moving too fast", "Not getting full range"],
                coachingCues: ["Rotate from ribs", "Keep hips still", "Look behind you"],
                requiredEquipment: [.none],
                alternativeExercises: ["world_greatest_stretch", "cat_cow"],
                movementPattern: .mobility
            ),
            
            Exercise(
                slug: "walking_leg_cradle",
                name: "Walking Leg Cradle",
                category: .mobility,
                primaryMuscles: [.hips, .glutes],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hip],
                defaultSets: 2,
                defaultReps: 8...10,
                defaultRestSeconds: 30,
                loadType: .bodyweight,
                loadGuidance: "Pull knee toward chest with gentle pressure",
                whyItHelpsRunners: "Opens up hip external rotation and glutes. Essential for runners with tight hips or piriformis issues.",
                commonMistakes: ["Hunching forward", "Not pulling knee high enough", "Losing balance"],
                coachingCues: ["Stay tall", "Pull knee to chest", "Hug shin gently"],
                requiredEquipment: [.none],
                alternativeExercises: ["hip_circles", "leg_swings_lateral"],
                movementPattern: .mobility
            ),
            
            Exercise(
                slug: "calf_stretch",
                name: "Calf Stretch (Wall)",
                category: .mobility,
                primaryMuscles: [.calves],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.calf, .achilles],
                defaultSets: 2,
                defaultDurationSeconds: 30,
                defaultRestSeconds: 20,
                loadType: .bodyweight,
                loadGuidance: "Hold gentle stretch, no bouncing",
                whyItHelpsRunners: "Lengthens chronically tight calves from repetitive running. Reduces Achilles strain and improves ankle mobility.",
                commonMistakes: ["Letting heel lift", "Bending back knee", "Not leaning far enough"],
                coachingCues: ["Back heel down", "Back knee straight", "Lean into wall"],
                requiredEquipment: [.none],
                alternativeExercises: ["ankle_mobility_drill", "eccentric_calf_lower"],
                movementPattern: .mobility
            ),
            
            // MARK: - Plyometric Exercises (6)
            
            Exercise(
                slug: "box_jump",
                name: "Box Jump",
                category: .plyometrics,
                primaryMuscles: [.quads, .glutes, .calves],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK],
                defaultSets: 3,
                defaultReps: 6...8,
                defaultRestSeconds: 120,
                loadType: .bodyweight,
                loadGuidance: "Focus on explosive takeoff and soft landing",
                whyItHelpsRunners: "Develops explosive power for faster starts and sprint finishes. Trains rapid force production critical for racing.",
                commonMistakes: ["Landing hard", "Not using arms", "Jumping down (step down instead)"],
                coachingCues: ["Swing arms", "Land softly", "Step down"],
                requiredEquipment: [.bench],
                alternativeExercises: ["jump_squat", "broad_jump"],
                movementPattern: .plyo,
                avoidIf: [.knee, .achilles]
            ),
            
            Exercise(
                slug: "jump_squat",
                name: "Jump Squat",
                category: .plyometrics,
                primaryMuscles: [.quads, .glutes],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK],
                defaultSets: 3,
                defaultReps: 8...10,
                defaultRestSeconds: 90,
                loadType: .bodyweight,
                loadGuidance: "Explosive jump, soft landing back to squat",
                whyItHelpsRunners: "Builds lower body power and reactive strength. Improves running economy by enhancing stretch-shortening cycle.",
                commonMistakes: ["Not squatting deep enough", "Landing stiff", "Rushing reps"],
                coachingCues: ["Squat low", "Explode up", "Absorb landing"],
                requiredEquipment: [.none],
                alternativeExercises: ["box_jump", "broad_jump"],
                movementPattern: .plyo,
                avoidIf: [.knee]
            ),
            
            Exercise(
                slug: "single_leg_bound",
                name: "Single-Leg Bound",
                category: .plyometrics,
                primaryMuscles: [.quads, .glutes, .calves],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK, .halfMarathon],
                defaultSets: 3,
                defaultReps: 6...8,
                defaultRestSeconds: 90,
                loadType: .bodyweight,
                loadGuidance: "Maximum distance per hop, not speed",
                whyItHelpsRunners: "Develops single-leg power and reactive strength specific to running. Improves stride length and ground contact efficiency.",
                commonMistakes: ["Too many quick hops instead of big bounds", "Poor landing mechanics", "Not using arms"],
                coachingCues: ["Big bounds", "Drive knee forward", "Stick landing"],
                requiredEquipment: [.none],
                alternativeExercises: ["box_jump", "skipping"],
                movementPattern: .plyo,
                avoidIf: [.knee, .achilles, .calf]
            ),
            
            Exercise(
                slug: "skipping",
                name: "High Skipping",
                category: .plyometrics,
                primaryMuscles: [.quads, .glutes, .calves],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon],
                defaultSets: 3,
                defaultReps: 20...30,
                defaultRestSeconds: 75,
                loadType: .bodyweight,
                loadGuidance: "Height and powerful ground contact, not speed",
                whyItHelpsRunners: "Develops explosive triple extension (ankle, knee, hip) used in sprinting. Improves coordination and rhythm.",
                commonMistakes: ["Not getting high enough", "Poor arm drive", "Landing heavy"],
                coachingCues: ["Drive knee high", "Powerful arm swing", "Spring off ground"],
                requiredEquipment: [.none],
                alternativeExercises: ["single_leg_bound", "pogo_hops"],
                movementPattern: .plyo
            ),
            
            Exercise(
                slug: "pogo_hops",
                name: "Pogo Hops",
                category: .plyometrics,
                primaryMuscles: [.calves],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon],
                injuryPreventionTags: [.calf],
                defaultSets: 3,
                defaultReps: 15...20,
                defaultRestSeconds: 60,
                loadType: .bodyweight,
                loadGuidance: "Minimal ground contact time, stay on toes",
                whyItHelpsRunners: "Develops elastic recoil in calves and Achilles. Improves running economy by enhancing reactive strength.",
                commonMistakes: ["Bending knees too much", "Landing on heels", "Not staying tall"],
                coachingCues: ["Stiff ankles", "Quick contacts", "Stay tall"],
                requiredEquipment: [.none],
                alternativeExercises: ["skipping", "single_leg_calf_raise"],
                movementPattern: .plyo,
                avoidIf: [.achilles, .calf]
            ),
            
            Exercise(
                slug: "broad_jump",
                name: "Broad Jump",
                category: .plyometrics,
                primaryMuscles: [.quads, .glutes, .calves],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK],
                defaultSets: 3,
                defaultReps: 5...6,
                defaultRestSeconds: 120,
                loadType: .bodyweight,
                loadGuidance: "Maximum distance with controlled landing",
                whyItHelpsRunners: "Develops horizontal power production. Tests and improves explosive strength without vertical impact.",
                commonMistakes: ["Not using arms", "Landing with locked knees", "Not measuring progress"],
                coachingCues: ["Swing arms back then forward", "Jump for distance", "Absorb landing"],
                requiredEquipment: [.none],
                alternativeExercises: ["box_jump", "jump_squat"],
                movementPattern: .plyo,
                avoidIf: [.knee]
            ),
            
            // MARK: - Prehab Exercises (4)
            
            Exercise(
                slug: "tibialis_raise",
                name: "Tibialis Raise",
                category: .prehab,
                primaryMuscles: [.shin],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.shin],
                defaultSets: 3,
                defaultReps: 15...20,
                defaultRestSeconds: 45,
                loadType: .bodyweight,
                loadGuidance: "Bodyweight, or use resistance band for more challenge",
                whyItHelpsRunners: "Strengthens the tibialis anterior, the primary muscle that prevents shin splints. Essential for high-mileage runners.",
                commonMistakes: ["Moving too fast", "Not getting full range", "Using momentum"],
                coachingCues: ["Toes to ceiling", "Control the lower", "Feel it in shins"],
                requiredEquipment: [.none],
                alternativeExercises: ["toe_walks", "ankle_mobility_drill"],
                movementPattern: .prehab
            ),
            
            Exercise(
                slug: "foot_strengthening",
                name: "Foot Strengthening (Towel Scrunches)",
                category: .prehab,
                primaryMuscles: [.calves],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.foot, .arch],
                defaultSets: 2,
                defaultReps: 15...20,
                defaultRestSeconds: 30,
                loadType: .bodyweight,
                loadGuidance: "Use toes to scrunch towel toward you",
                whyItHelpsRunners: "Strengthens intrinsic foot muscles and arch. Reduces plantar fasciitis risk and improves foot stability.",
                commonMistakes: ["Using whole leg", "Not fully scrunching", "Rushing"],
                coachingCues: ["Toes only", "Pull towel", "Feel arch working"],
                requiredEquipment: [.none],
                alternativeExercises: ["single_leg_balance", "toe_walks"],
                movementPattern: .prehab
            ),
            
            Exercise(
                slug: "toe_walks",
                name: "Toe Walks",
                category: .prehab,
                primaryMuscles: [.calves],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.calf, .achilles],
                defaultSets: 2,
                defaultDurationSeconds: 30,
                defaultRestSeconds: 30,
                loadType: .bodyweight,
                loadGuidance: "Walk on toes, stay as high as possible",
                whyItHelpsRunners: "Builds calf endurance and Achilles resilience. Simple but effective strengthening for lower leg.",
                commonMistakes: ["Not staying high on toes", "Bouncing", "Moving too fast"],
                coachingCues: ["Stay tall on toes", "Small steps", "Don't let heels drop"],
                requiredEquipment: [.none],
                alternativeExercises: ["single_leg_calf_raise", "pogo_hops"],
                movementPattern: .prehab
            ),
            
            Exercise(
                slug: "hip_flexor_stretch",
                name: "Hip Flexor Stretch (Kneeling)",
                category: .prehab,
                primaryMuscles: [.hips],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hip],
                defaultSets: 2,
                defaultDurationSeconds: 30,
                defaultRestSeconds: 20,
                loadType: .bodyweight,
                loadGuidance: "Gentle stretch, no pain",
                whyItHelpsRunners: "Lengthens chronically tight hip flexors. Improves running stride and reduces lower back compensation.",
                commonMistakes: ["Arching lower back", "Not engaging glute", "Leaning too far forward"],
                coachingCues: ["Squeeze glute", "Tuck pelvis", "Feel stretch in front of hip"],
                requiredEquipment: [.none],
                alternativeExercises: ["world_greatest_stretch", "walking_leg_cradle"],
                movementPattern: .mobility
            ),
            
            // MARK: - Additional Strength Exercises (7)
            
            Exercise(
                slug: "pull_up",
                name: "Pull-up",
                category: .strength,
                primaryMuscles: [.core],
                secondaryMuscles: [],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.lowerBack],
                defaultSets: 3,
                defaultReps: 5...10,
                defaultRestSeconds: 90,
                loadType: .bodyweight,
                loadGuidance: "Full range of motion - chin over bar at top, full extension at bottom",
                whyItHelpsRunners: "Strengthens upper body and core for better running posture. Prevents slouching during long runs and reduces lower back fatigue.",
                commonMistakes: ["Not going full range", "Kipping/swinging", "Rushing the movement"],
                coachingCues: ["Hang fully extended", "Pull chin over bar", "Control the descent"],
                requiredEquipment: [.pullUpBar],
                alternativeExercises: ["assisted_pull_up"],
                movementPattern: .core
            ),
            
            Exercise(
                slug: "assisted_pull_up",
                name: "Assisted Pull-up",
                category: .strength,
                primaryMuscles: [.core],
                secondaryMuscles: [],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.lowerBack],
                defaultSets: 3,
                defaultReps: 8...12,
                defaultRestSeconds: 75,
                loadType: .bodyweight,
                loadGuidance: "Use resistance band or assisted pull-up machine to reduce bodyweight",
                whyItHelpsRunners: "Builds upper body strength for runners who can't yet do full pull-ups. Improves posture and core stability.",
                commonMistakes: ["Using too much assistance", "Not going full range", "Rushing"],
                coachingCues: ["Use minimal assistance needed", "Full range of motion", "Control both directions"],
                requiredEquipment: [.pullUpBar, .resistanceBands],
                alternativeExercises: ["pull_up"],
                movementPattern: .core
            ),
            
            Exercise(
                slug: "step_up",
                name: "Step-up",
                category: .strength,
                primaryMuscles: [.quads, .glutes],
                secondaryMuscles: [.hamstrings],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.knee],
                defaultSets: 3,
                defaultReps: 10...15,
                defaultRestSeconds: 75,
                loadType: .fixedRecommendation,
                loadGuidance: "Can use dumbbells or bodyweight. Focus on driving through heel of stepping leg.",
                whyItHelpsRunners: "Develops single-leg power and stability. Mimics the action of running uphill and improves push-off strength.",
                commonMistakes: ["Pushing off back foot", "Not fully extending hip", "Knee caving in"],
                coachingCues: ["Drive through front heel", "Full hip extension", "Keep knee aligned"],
                requiredEquipment: [.plyoBox],
                alternativeExercises: ["bulgarian_split_squat", "reverse_lunge"],
                movementPattern: .lunge
            ),
            
            Exercise(
                slug: "box_squat",
                name: "Box Squat",
                category: .strength,
                primaryMuscles: [.quads, .glutes],
                secondaryMuscles: [.hamstrings],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.knee],
                defaultSets: 3,
                defaultReps: 8...12,
                defaultRestSeconds: 90,
                loadType: .fixedRecommendation,
                loadGuidance: "Can use barbell or dumbbells. Sit back onto box, pause, then drive up.",
                whyItHelpsRunners: "Teaches proper squat depth and hip mechanics. Builds posterior chain strength for powerful running stride.",
                commonMistakes: ["Not sitting back enough", "Bouncing off box", "Leaning too far forward"],
                coachingCues: ["Sit back onto box", "Pause briefly", "Drive through heels"],
                requiredEquipment: [.plyoBox],
                alternativeExercises: ["goblet_squat", "bodyweight_squat"],
                movementPattern: .squat
            ),
            
            Exercise(
                slug: "sled_push",
                name: "Sled Push",
                category: .strength,
                primaryMuscles: [.quads, .glutes, .calves],
                secondaryMuscles: [.core],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK],
                defaultSets: 3,
                defaultReps: 20...30,
                defaultRestSeconds: 120,
                loadType: .fixedRecommendation,
                loadGuidance: "Load sled moderately - focus on powerful leg drive, not maximum weight",
                whyItHelpsRunners: "Develops horizontal force production specific to running. Builds power without eccentric loading that can cause soreness.",
                commonMistakes: ["Too much weight", "Leaning too far forward", "Short steps"],
                coachingCues: ["Powerful leg drive", "Stay tall", "Full strides"],
                requiredEquipment: [.sled],
                alternativeExercises: ["broad_jump", "single_leg_bound"],
                movementPattern: .plyo
            ),
            
            Exercise(
                slug: "landmine_single_leg_rdl",
                name: "Landmine Single-Leg RDL",
                category: .strength,
                primaryMuscles: [.hamstrings, .glutes],
                secondaryMuscles: [.core],
                runnerBenefit: .injuryPrevention,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hamstring, .knee],
                defaultSets: 3,
                defaultReps: 8...12,
                defaultRestSeconds: 75,
                loadType: .fixedRecommendation,
                loadGuidance: "Hold barbell end, hinge at hip while balancing on one leg",
                whyItHelpsRunners: "Excellent alternative to dumbbell RDL. The landmine provides unique resistance angle that challenges stability while strengthening posterior chain.",
                commonMistakes: ["Rounding back", "Bending knee too much", "Losing balance"],
                coachingCues: ["Hinge at hip", "Keep back flat", "Drive heel into ground"],
                requiredEquipment: [.landmineAttachment, .barbell],
                alternativeExercises: ["single_leg_rdl", "nordic_curl"],
                movementPattern: .hinge,
                avoidIf: [.hamstring]
            ),
            
            Exercise(
                slug: "trx_single_leg_squat",
                name: "TRX Single-Leg Squat",
                category: .strength,
                primaryMuscles: [.quads, .glutes],
                secondaryMuscles: [.core, .hips],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .general],
                injuryPreventionTags: [.knee],
                defaultSets: 3,
                defaultReps: 8...12,
                defaultRestSeconds: 90,
                loadType: .bodyweight,
                loadGuidance: "Use TRX for assistance - progress by using less support over time",
                whyItHelpsRunners: "Builds single-leg strength with assistance for those who can't do full pistol squats. Develops balance and control essential for running.",
                commonMistakes: ["Using too much assistance", "Knee collapsing inward", "Not going deep enough"],
                coachingCues: ["Use minimal assistance", "Keep knee aligned", "Sit back into heel"],
                requiredEquipment: [.trxBands],
                alternativeExercises: ["single_leg_squat", "bulgarian_split_squat"],
                movementPattern: .squat
            ),
            
            // MARK: - Additional Stability Exercises (4)
            
            Exercise(
                slug: "stability_ball_plank",
                name: "Stability Ball Plank",
                category: .stability,
                primaryMuscles: [.core],
                secondaryMuscles: [],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.lowerBack],
                defaultSets: 3,
                defaultDurationSeconds: 30,
                defaultRestSeconds: 60,
                loadType: .bodyweight,
                loadGuidance: "Place feet on stability ball, maintain straight line from head to heels",
                whyItHelpsRunners: "Advanced core stability challenge. The unstable surface forces greater core engagement than standard plank.",
                commonMistakes: ["Hips sagging", "Shoulders shrugging", "Holding breath"],
                coachingCues: ["Body straight as board", "Squeeze glutes", "Breathe steadily"],
                requiredEquipment: [.stabilityBall],
                alternativeExercises: ["plank", "dead_bug"],
                movementPattern: .core
            ),
            
            Exercise(
                slug: "trx_fallout",
                name: "TRX Fallout",
                category: .stability,
                primaryMuscles: [.core],
                secondaryMuscles: [],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.lowerBack],
                defaultSets: 3,
                defaultReps: 8...12,
                defaultRestSeconds: 60,
                loadType: .bodyweight,
                loadGuidance: "Start in plank position, extend arms forward while maintaining plank",
                whyItHelpsRunners: "Advanced anti-extension core work. Challenges core stability under load, improving running posture and efficiency.",
                commonMistakes: ["Hips sagging", "Moving too far forward", "Losing plank position"],
                coachingCues: ["Maintain plank", "Extend slowly", "Feel core working"],
                requiredEquipment: [.trxBands],
                alternativeExercises: ["plank", "dead_bug"],
                movementPattern: .core
            ),
            
            Exercise(
                slug: "wall_ball_rotational_throw",
                name: "Wall Ball Rotational Throw",
                category: .stability,
                primaryMuscles: [.core],
                secondaryMuscles: [.hips],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.lowerBack],
                defaultSets: 3,
                defaultReps: 8...10,
                defaultRestSeconds: 75,
                loadType: .fixedRecommendation,
                loadGuidance: "Use moderate weight wall ball. Rotate and throw against wall, catch and rotate back",
                whyItHelpsRunners: "Develops rotational power and core stability. Improves ability to maintain form during long runs when fatigue sets in.",
                commonMistakes: ["Using arms only", "Not rotating from core", "Poor catching technique"],
                coachingCues: ["Rotate from core", "Use legs to drive", "Catch and control"],
                requiredEquipment: [.wallBall],
                alternativeExercises: ["plank", "dead_bug"],
                movementPattern: .core
            ),
            
            Exercise(
                slug: "ghd_hip_extension",
                name: "GHD Hip Extension",
                category: .stability,
                primaryMuscles: [.glutes, .hamstrings],
                secondaryMuscles: [.core],
                runnerBenefit: .stability,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.hip, .knee],
                defaultSets: 3,
                defaultReps: 10...15,
                defaultRestSeconds: 75,
                loadType: .bodyweight,
                loadGuidance: "Start with bodyweight, can add weight plate for progression",
                whyItHelpsRunners: "Excellent glute and hamstring strengthening with core stability challenge. Builds posterior chain strength critical for running power.",
                commonMistakes: ["Hyperextending back", "Not fully extending hips", "Moving too fast"],
                coachingCues: ["Squeeze glutes", "Full hip extension", "Control the movement"],
                requiredEquipment: [.ghdMachine],
                alternativeExercises: ["glute_bridge", "hip_thrust"],
                movementPattern: .hinge
            ),
            
            // MARK: - Additional Prehab Exercises (4)
            
            Exercise(
                slug: "foam_roll_it_band",
                name: "Foam Roll IT Band",
                category: .prehab,
                primaryMuscles: [.hips],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.knee, .hip],
                defaultSets: 1,
                defaultDurationSeconds: 60,
                defaultRestSeconds: 0,
                loadType: .bodyweight,
                loadGuidance: "Roll slowly along IT band from hip to knee. Pause on tender spots for 30 seconds",
                whyItHelpsRunners: "Releases tension in IT band that can cause knee pain. Essential recovery tool for high-mileage runners.",
                commonMistakes: ["Rolling too fast", "Skipping tender spots", "Not breathing"],
                coachingCues: ["Slow rolls", "Pause on tight spots", "Breathe through discomfort"],
                requiredEquipment: [.foamRoller],
                alternativeExercises: ["hip_flexor_stretch", "lateral_band_walk"],
                movementPattern: .prehab
            ),
            
            Exercise(
                slug: "foam_roll_calves",
                name: "Foam Roll Calves",
                category: .prehab,
                primaryMuscles: [.calves],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.calf, .achilles],
                defaultSets: 1,
                defaultDurationSeconds: 60,
                defaultRestSeconds: 0,
                loadType: .bodyweight,
                loadGuidance: "Roll slowly along calf muscles. Point and flex foot to target different areas",
                whyItHelpsRunners: "Releases tight calf muscles that can lead to Achilles issues and plantar fasciitis. Critical recovery tool for runners.",
                commonMistakes: ["Rolling too fast", "Not covering full calf", "Skipping tender spots"],
                coachingCues: ["Slow rolls", "Point and flex foot", "Pause on tight spots"],
                requiredEquipment: [.foamRoller],
                alternativeExercises: ["calf_stretch", "eccentric_calf_lower"],
                movementPattern: .prehab
            ),
            
            Exercise(
                slug: "banded_ankle_mobility",
                name: "Banded Ankle Mobility",
                category: .prehab,
                primaryMuscles: [.calves],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.ankle, .calf, .achilles],
                defaultSets: 2,
                defaultReps: 10...12,
                defaultRestSeconds: 30,
                loadType: .bodyweight,
                loadGuidance: "Loop band around ankle, drive knee forward over toes while band pulls back",
                whyItHelpsRunners: "Improves ankle dorsiflexion with resistance. Critical for proper foot strike and push-off mechanics.",
                commonMistakes: ["Heel lifting", "Not driving knee forward enough", "Moving too fast"],
                coachingCues: ["Heel stays down", "Drive knee past toes", "Feel stretch in calf"],
                requiredEquipment: [.resistanceBands],
                alternativeExercises: ["ankle_mobility_drill", "calf_stretch"],
                movementPattern: .mobility
            ),
            
            Exercise(
                slug: "wall_calf_stretch",
                name: "Wall Calf Stretch",
                category: .prehab,
                primaryMuscles: [.calves],
                runnerBenefit: .mobility,
                supportsGoals: [.fiveK, .tenK, .halfMarathon, .marathon, .general],
                injuryPreventionTags: [.calf, .achilles],
                defaultSets: 2,
                defaultDurationSeconds: 30,
                defaultRestSeconds: 20,
                loadType: .bodyweight,
                loadGuidance: "Place foot against wall, lean forward to feel stretch in calf",
                whyItHelpsRunners: "Static stretch for tight calves. Use after runs to maintain flexibility and prevent Achilles issues.",
                commonMistakes: ["Not leaning far enough", "Bending back knee", "Rushing the stretch"],
                coachingCues: ["Lean into wall", "Back knee straight", "Hold gentle stretch"],
                requiredEquipment: [.yogaMat],
                alternativeExercises: ["calf_stretch", "foam_roll_calves"],
                movementPattern: .mobility
            ),
            
            // MARK: - Additional Plyometric Exercises (3)
            
            Exercise(
                slug: "box_step_down",
                name: "Box Step-down",
                category: .plyometrics,
                primaryMuscles: [.quads, .glutes],
                secondaryMuscles: [.calves],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK, .halfMarathon],
                injuryPreventionTags: [.knee],
                defaultSets: 3,
                defaultReps: 8...12,
                defaultRestSeconds: 90,
                loadType: .bodyweight,
                loadGuidance: "Step down slowly, controlling the eccentric loading. Focus on soft landing",
                whyItHelpsRunners: "Develops eccentric control and landing mechanics. Trains the muscles to absorb impact efficiently, reducing injury risk.",
                commonMistakes: ["Dropping down too fast", "Poor landing mechanics", "Knee caving in"],
                coachingCues: ["Control the step down", "Soft landing", "Keep knee aligned"],
                requiredEquipment: [.plyoBox],
                alternativeExercises: ["box_jump", "step_up"],
                movementPattern: .plyo,
                avoidIf: [.knee]
            ),
            
            Exercise(
                slug: "lateral_box_hop",
                name: "Lateral Box Hop",
                category: .plyometrics,
                primaryMuscles: [.quads, .glutes, .hips],
                secondaryMuscles: [.calves],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK],
                defaultSets: 3,
                defaultReps: 6...8,
                defaultRestSeconds: 90,
                loadType: .bodyweight,
                loadGuidance: "Hop laterally onto box, step down, repeat on other side",
                whyItHelpsRunners: "Develops lateral power and hip stability. Improves ability to change direction and handle uneven terrain.",
                commonMistakes: ["Landing hard", "Not using arms", "Poor balance"],
                coachingCues: ["Swing arms", "Land softly", "Step down safely"],
                requiredEquipment: [.plyoBox],
                alternativeExercises: ["box_jump", "lateral_lunge"],
                movementPattern: .plyo,
                avoidIf: [.knee, .hip]
            ),
            
            Exercise(
                slug: "sled_sprint",
                name: "Sled Sprint",
                category: .plyometrics,
                primaryMuscles: [.quads, .glutes, .calves],
                secondaryMuscles: [.core],
                runnerBenefit: .powerDevelopment,
                supportsGoals: [.fiveK, .tenK],
                defaultSets: 3,
                defaultReps: 20...30,
                defaultRestSeconds: 120,
                loadType: .fixedRecommendation,
                loadGuidance: "Moderate weight - focus on powerful leg drive and full strides",
                whyItHelpsRunners: "Resisted sprint training develops explosive power and speed. Improves acceleration and top-end speed without high impact.",
                commonMistakes: ["Too much weight", "Short choppy steps", "Leaning too far forward"],
                coachingCues: ["Powerful leg drive", "Full strides", "Stay tall"],
                requiredEquipment: [.sled],
                alternativeExercises: ["sled_push", "single_leg_bound"],
                movementPattern: .plyo
            ),
        ]
        
        // Build lookup dictionary
        for exercise in allExercises {
            exercisesBySlug[exercise.slug] = exercise
        }
    }
    
    // MARK: - Validation
    
    private func validateLibrary() {
        var validationErrors: [String] = []
        
        for exercise in allExercises {
            // Check primary muscles
            if exercise.primaryMuscles.isEmpty {
                validationErrors.append("Exercise '\(exercise.slug)' has no primary muscles")
            }
            
            // Check alternative exercises exist
            for altSlug in exercise.alternativeExercises {
                if exercisesBySlug[altSlug] == nil {
                    validationErrors.append("Exercise '\(exercise.slug)' references non-existent alternative '\(altSlug)'")
                }
            }
        }
        
        // Check for circular references
        for exercise in allExercises {
            for altSlug in exercise.alternativeExercises {
                if let altExercise = exercisesBySlug[altSlug] {
                    if altExercise.alternativeExercises.contains(exercise.slug) {
                        validationErrors.append("Circular alternative reference between '\(exercise.slug)' and '\(altSlug)'")
                    }
                }
            }
        }
        
        if !validationErrors.isEmpty {
            print("⚠️ Exercise Library Validation Errors:")
            for error in validationErrors {
                print("  - \(error)")
            }
        } else {
            print("✅ Exercise Library validated successfully: \(allExercises.count) exercises")
        }
    }
    
    // MARK: - Public Query Methods
    
    /// Get exercise by slug
    func getExercise(slug: String) -> Exercise? {
        return exercisesBySlug[slug]
    }
    
    /// Get exercise by UUID (convenience)
    func getExercise(id: UUID) -> Exercise? {
        return allExercises.first { $0.id == id }
    }
    
    /// Filter exercises by available equipment
    func filterByEquipment(_ equipment: Set<GymEquipment>) -> [Exercise] {
        return allExercises.filter { exercise in
            // Exercise is available if all required equipment is in the available set
            Set(exercise.requiredEquipment).isSubset(of: equipment)
        }
    }
    
    /// Filter exercises by category
    func filterByCategory(_ category: ExerciseCategory) -> [Exercise] {
        return allExercises.filter { $0.category == category }
    }
    
    /// Filter exercises by goal type
    func filterByGoal(_ goalType: ExerciseGoalType) -> [Exercise] {
        return allExercises.filter { $0.supportsGoals.contains(goalType) }
    }
    
    /// Find curated alternatives for an exercise
    func findAlternatives(for exerciseSlug: String) -> [Exercise] {
        guard let exercise = getExercise(slug: exerciseSlug) else { return [] }
        return exercise.alternativeExercises.compactMap { getExercise(slug: $0) }
    }
    
    /// Find alternatives by movement pattern (fallback when curated alternatives don't exist)
    func findAlternativesByPattern(
        _ pattern: MovementPattern,
        equipment: Set<GymEquipment>,
        excluding: [String] = []
    ) -> [Exercise] {
        return allExercises.filter { exercise in
            exercise.movementPattern == pattern &&
            Set(exercise.requiredEquipment).isSubset(of: equipment) &&
            !excluding.contains(exercise.slug)
        }
    }
    
    /// Get exercises for a specific muscle group
    func filterByMuscleGroup(_ muscleGroup: MuscleGroup) -> [Exercise] {
        return allExercises.filter {
            $0.primaryMuscles.contains(muscleGroup) || $0.secondaryMuscles.contains(muscleGroup)
        }
    }
    
    /// Get exercises safe for specific injury areas
    func filterSafeFor(injuryAreas: [InjuryArea]) -> [Exercise] {
        return allExercises.filter { exercise in
            Set(exercise.avoidIf).isDisjoint(with: Set(injuryAreas))
        }
    }
}
