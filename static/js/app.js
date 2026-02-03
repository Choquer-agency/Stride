/**
 * Stride - AI Running Coach
 * Form handling and plan generation
 */

// State
let currentStep = 1;
const totalSteps = 5;  // Now includes conflict resolution step
let generatedPlan = '';
let conflictAnalysis = null;  // Stores conflict analysis response
let selectedPlanMode = null;  // 'aggressive' or 'recommended'

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initializeDates();
    setupFormSubmission();
    setupScheduleValidation();
});

/**
 * Auto-select optimal running and gym days based on race distance and fitness level
 */
function autoSelectSchedule() {
    const raceType = document.querySelector('select[name="race_type"]').value;
    const fitnessLevel = document.querySelector('select[name="fitness_level"]').value;
    
    let runningDays = 5;
    let gymDays = 2;
    
    // Determine optimal schedule based on race type and fitness level
    const isUltra = ['50K', '80K', '100K', '160K', '160+ km'].includes(raceType);
    const isMarathonDistance = ['Half Marathon', 'Marathon'].includes(raceType);
    const isSpeedDistance = ['5K', '10K'].includes(raceType);
    const isBeginner = fitnessLevel === 'beginner';
    const isAdvanced = fitnessLevel === 'advanced';
    
    if (isUltra) {
        // Ultra distances: high running volume, moderate strength work
        runningDays = isAdvanced ? 6 : 5;
        gymDays = 2;
    } else if (isMarathonDistance) {
        // Marathon/Half: balance of running and strength
        if (isBeginner) {
            runningDays = 4;
            gymDays = 2;
        } else if (isAdvanced) {
            runningDays = 6;
            gymDays = 1;
        } else {
            runningDays = 5;
            gymDays = 2;
        }
    } else if (isSpeedDistance) {
        // 5K/10K: more recovery for quality sessions
        if (isBeginner) {
            runningDays = 3;
            gymDays = 2;
        } else if (isAdvanced) {
            runningDays = 5;
            gymDays = 2;
        } else {
            runningDays = 4;
            gymDays = 2;
        }
    }
    
    // Update the select dropdowns
    const runningSelect = document.getElementById('running_days_select');
    const gymSelect = document.getElementById('gym_days_select');
    
    if (runningSelect) {
        runningSelect.value = runningDays;
    }
    if (gymSelect) {
        gymSelect.value = gymDays;
    }
    
    // Show feedback to user
    showToast('Schedule optimized for your goal!');
    
    // Re-validate after auto-selection
    validateScheduleConfiguration();
}

/**
 * Set up event listeners for schedule validation
 */
function setupScheduleValidation() {
    // Listen for changes on rest day checkboxes
    document.querySelectorAll('input[name="rest_days"]').forEach(checkbox => {
        checkbox.addEventListener('change', validateScheduleConfiguration);
    });
    
    // Listen for changes on running days dropdown
    const runningSelect = document.getElementById('running_days_select');
    if (runningSelect) {
        runningSelect.addEventListener('change', validateScheduleConfiguration);
    }
    
    // Listen for changes on gym days dropdown
    const gymSelect = document.getElementById('gym_days_select');
    if (gymSelect) {
        gymSelect.addEventListener('change', validateScheduleConfiguration);
    }
    
    // Listen for changes on double days toggle
    const doubleDaysToggle = document.querySelector('input[name="double_days_allowed"]');
    if (doubleDaysToggle) {
        doubleDaysToggle.addEventListener('change', validateScheduleConfiguration);
    }
    
    // Initial validation
    validateScheduleConfiguration();
}

/**
 * Validate the schedule configuration
 * Returns true if valid, false if invalid
 */
function validateScheduleConfiguration() {
    // Get selected rest days count
    const restDaysCount = document.querySelectorAll('input[name="rest_days"]:checked').length;
    
    // Get running and gym days
    const runningDays = parseInt(document.getElementById('running_days_select')?.value || 5);
    const gymDays = parseInt(document.getElementById('gym_days_select')?.value || 2);
    
    // Get double days toggle
    const doubleDaysAllowed = document.querySelector('input[name="double_days_allowed"]')?.checked || false;
    
    // Calculate available days and total sessions
    const availableDays = 7 - restDaysCount;
    const totalSessions = runningDays + gymDays;
    
    // Determine if configuration is valid
    const needsStacking = totalSessions > availableDays;
    const isValid = !needsStacking || doubleDaysAllowed;
    
    // Update UI
    updateScheduleValidationUI(isValid, {
        availableDays,
        totalSessions,
        runningDays,
        gymDays,
        restDaysCount,
        doubleDaysAllowed,
        needsStacking
    });
    
    return isValid;
}

/**
 * Update the schedule validation UI feedback
 */
function updateScheduleValidationUI(isValid, info) {
    // Find or create the validation message container
    let validationContainer = document.getElementById('schedule-validation-message');
    
    if (!validationContainer) {
        // Create the container after the training volume section
        const volumeSection = document.querySelector('.training-volume-section');
        if (volumeSection) {
            validationContainer = document.createElement('div');
            validationContainer.id = 'schedule-validation-message';
            validationContainer.style.cssText = `
                margin-top: 16px;
                padding: 12px 16px;
                border-radius: var(--radius-md);
                font-size: 0.9rem;
                display: none;
            `;
            volumeSection.appendChild(validationContainer);
        }
    }
    
    if (!validationContainer) return;
    
    if (!isValid) {
        // Show error message
        validationContainer.style.display = 'block';
        validationContainer.style.background = 'rgba(239, 68, 68, 0.1)';
        validationContainer.style.border = '1px solid rgba(239, 68, 68, 0.3)';
        validationContainer.style.color = 'var(--text-primary)';
        
        const sessionsNeeded = info.totalSessions;
        const daysAvailable = info.availableDays;
        const stackingRequired = sessionsNeeded - daysAvailable;
        
        validationContainer.innerHTML = `
            <div style="display: flex; align-items: flex-start; gap: 10px;">
                <span style="font-size: 1.2rem;">⚠️</span>
                <div>
                    <strong>Schedule Conflict</strong><br>
                    You need ${sessionsNeeded} sessions (${info.runningDays} runs + ${info.gymDays} gym) but only have ${daysAvailable} available days after ${info.restDaysCount} rest day${info.restDaysCount !== 1 ? 's' : ''}.<br>
                    <span style="opacity: 0.8;">Enable "Allow Double Days" to stack ${stackingRequired} gym session${stackingRequired !== 1 ? 's' : ''} with runs, or reduce sessions/rest days.</span>
                </div>
            </div>
        `;
    } else if (info.needsStacking && info.doubleDaysAllowed) {
        // Show info message about stacking
        validationContainer.style.display = 'block';
        validationContainer.style.background = 'rgba(59, 130, 246, 0.1)';
        validationContainer.style.border = '1px solid rgba(59, 130, 246, 0.3)';
        validationContainer.style.color = 'var(--text-primary)';
        
        const stackingRequired = info.totalSessions - info.availableDays;
        
        validationContainer.innerHTML = `
            <div style="display: flex; align-items: flex-start; gap: 10px;">
                <span style="font-size: 1.2rem;">ℹ️</span>
                <div>
                    <strong>Stacking Required</strong><br>
                    ${stackingRequired} gym session${stackingRequired !== 1 ? 's' : ''} will be combined with easy run days to fit your schedule.
                </div>
            </div>
        `;
    } else {
        // Hide message when valid with no stacking needed
        validationContainer.style.display = 'none';
    }
}

/**
 * Set default dates (start date = today, race date = 12 weeks from now)
 */
function initializeDates() {
    const today = new Date();
    const startDateInput = document.querySelector('input[name="start_date"]');
    const raceDateInput = document.querySelector('input[name="race_date"]');
    
    // Format as YYYY-MM-DD
    const formatDate = (date) => date.toISOString().split('T')[0];
    
    // Default start date: next Monday
    const nextMonday = new Date(today);
    nextMonday.setDate(today.getDate() + ((8 - today.getDay()) % 7 || 7));
    startDateInput.value = formatDate(nextMonday);
    
    // Default race date: 12 weeks from start
    const raceDate = new Date(nextMonday);
    raceDate.setDate(nextMonday.getDate() + 84); // 12 weeks
    raceDateInput.value = formatDate(raceDate);
    
    // Set min dates
    startDateInput.min = formatDate(today);
    raceDateInput.min = formatDate(new Date(today.getTime() + 14 * 24 * 60 * 60 * 1000)); // At least 2 weeks
}

/**
 * Navigate to next step
 */
function nextStep() {
    if (!validateCurrentStep()) return;
    
    if (currentStep < totalSteps) {
        setStep(currentStep + 1);
    }
}

/**
 * Navigate to previous step
 */
function prevStep() {
    if (currentStep > 1) {
        // If on conflict resolution step, go back to step 4
        if (currentStep === 5) {
            setStep(4);
        } else {
            setStep(currentStep - 1);
        }
    }
}

/**
 * Set the active step
 */
function setStep(step) {
    // Update step visibility
    document.querySelectorAll('.form-step').forEach(el => {
        el.classList.remove('active');
    });
    const stepEl = document.querySelector(`.form-step[data-step="${step}"]`);
    if (stepEl) {
        stepEl.classList.add('active');
    }
    
    // Update progress indicators (step 5 is conflict resolution, shown as a special state)
    document.querySelectorAll('.progress-step').forEach(el => {
        const stepNum = parseInt(el.dataset.step);
        el.classList.remove('active', 'completed');
        
        if (step === 5) {
            // All 4 steps are completed when on conflict resolution
            el.classList.add('completed');
        } else if (stepNum === step) {
            el.classList.add('active');
        } else if (stepNum < step) {
            el.classList.add('completed');
        }
    });
    
    // Show/hide the conflict resolution progress indicator
    const conflictProgress = document.getElementById('conflictProgressStep');
    if (conflictProgress) {
        if (step === 5) {
            conflictProgress.style.display = 'flex';
            conflictProgress.classList.add('active');
        } else {
            conflictProgress.style.display = 'none';
            conflictProgress.classList.remove('active');
        }
    }
    
    currentStep = step;
    
    // Scroll to top of form
    document.getElementById('formCard').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

/**
 * Validate current step's required fields
 */
function validateCurrentStep() {
    const currentStepEl = document.querySelector(`.form-step[data-step="${currentStep}"]`);
    const requiredFields = currentStepEl.querySelectorAll('[required]');
    
    let isValid = true;
    
    requiredFields.forEach(field => {
        if (!field.value.trim()) {
            field.style.borderColor = 'var(--primary)';
            isValid = false;
            
            // Reset border after a moment
            setTimeout(() => {
                field.style.borderColor = '';
            }, 2000);
        }
    });
    
    if (!isValid) {
        // Find first invalid field and focus it
        const firstInvalid = currentStepEl.querySelector('[required]:invalid, [required][value=""]');
        if (firstInvalid) {
            firstInvalid.focus();
        }
    }
    
    // Additional validation for step 3 (Schedule)
    if (currentStep === 3 && isValid) {
        const scheduleValid = validateScheduleConfiguration();
        if (!scheduleValid) {
            showToast('Please fix the schedule conflict before continuing');
            // Scroll to the validation message
            const validationMessage = document.getElementById('schedule-validation-message');
            if (validationMessage) {
                validationMessage.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
            return false;
        }
    }
    
    return isValid;
}

/**
 * Setup form submission
 */
function setupFormSubmission() {
    const form = document.getElementById('trainingForm');
    
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        
        if (!validateCurrentStep()) return;
        
        // If we're on step 4, analyze conflicts first
        if (currentStep === 4) {
            await analyzeConflicts();
        } else {
            await generatePlan();
        }
    });
}

/**
 * Analyze conflicts between goals and current fitness
 */
async function analyzeConflicts() {
    const loadingIndicator = document.getElementById('loadingIndicator');
    
    // Show loading
    document.querySelectorAll('.form-step').forEach(el => el.classList.remove('active'));
    loadingIndicator.classList.add('active');
    document.getElementById('loadingText').textContent = 'Analyzing your profile...';
    
    // Collect data
    const payload = collectFormData();
    
    try {
        const response = await fetch('/api/analyze-conflicts', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(payload)
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to analyze profile');
        }
        
        conflictAnalysis = await response.json();
        loadingIndicator.classList.remove('active');
        
        // If conflicts detected, show conflict resolution step
        if (conflictAnalysis.has_conflicts) {
            displayConflicts(conflictAnalysis);
            setStep(5);
        } else {
            // No conflicts, proceed directly to plan generation
            selectedPlanMode = null;
            await generatePlan();
        }
        
    } catch (error) {
        console.error('Analysis error:', error);
        loadingIndicator.classList.remove('active');
        showToast('Error analyzing profile: ' + error.message);
        setStep(4);  // Go back to step 4
    }
}

/**
 * Display detected conflicts in the UI
 */
function displayConflicts(analysis) {
    const conflictsList = document.getElementById('conflictsList');
    const goalComparison = document.getElementById('goalComparison');
    const conflictSummary = document.getElementById('conflictSummary');
    
    if (!conflictsList) return;
    
    // Clear previous conflicts
    conflictsList.innerHTML = '';
    
    // Add each conflict card
    analysis.conflicts.forEach(conflict => {
        const riskClass = conflict.risk_level === 'high' ? 'risk-high' : 
                          conflict.risk_level === 'medium' ? 'risk-medium' : 'risk-low';
        const riskIcon = conflict.risk_level === 'high' ? '🔴' : 
                         conflict.risk_level === 'medium' ? '🟡' : '🟢';
        
        const card = document.createElement('div');
        card.className = `conflict-card ${riskClass}`;
        card.innerHTML = `
            <div class="conflict-header">
                <span class="conflict-icon">${riskIcon}</span>
                <h4 class="conflict-title">${conflict.title}</h4>
            </div>
            <p class="conflict-description">${conflict.description}</p>
            <p class="conflict-recommendation"><strong>Recommendation:</strong> ${conflict.recommendation}</p>
        `;
        conflictsList.appendChild(card);
    });
    
    // Show goal comparison if we have both goals
    if (goalComparison && analysis.original_goal_time && analysis.recommended_goal_time && 
        analysis.original_goal_time !== analysis.recommended_goal_time) {
        goalComparison.style.display = 'block';
        goalComparison.innerHTML = `
            <div class="goal-comparison-content">
                <div class="goal-box original">
                    <span class="goal-label">Your Goal</span>
                    <span class="goal-time">${analysis.original_goal_time}</span>
                </div>
                <div class="goal-arrow">→</div>
                <div class="goal-box recommended">
                    <span class="goal-label">Recommended</span>
                    <span class="goal-time">${analysis.recommended_goal_time}</span>
                </div>
            </div>
        `;
    } else if (goalComparison) {
        goalComparison.style.display = 'none';
    }
    
    // Show summary
    if (conflictSummary && analysis.recommendation_summary) {
        conflictSummary.textContent = analysis.recommendation_summary;
    }
}

/**
 * Handle user's decision on conflict resolution
 */
function selectPlanMode(mode) {
    selectedPlanMode = mode;
    
    // Update button states
    document.querySelectorAll('.mode-btn').forEach(btn => {
        btn.classList.remove('selected');
    });
    
    const selectedBtn = document.querySelector(`.mode-btn[data-mode="${mode}"]`);
    if (selectedBtn) {
        selectedBtn.classList.add('selected');
    }
    
    // Enable the generate button
    const generateBtn = document.getElementById('conflictGenerateBtn');
    if (generateBtn) {
        generateBtn.disabled = false;
    }
}

/**
 * Generate plan after conflict resolution
 */
async function generatePlanWithMode() {
    if (!selectedPlanMode) {
        showToast('Please select a plan approach');
        return;
    }
    
    await generatePlan();
}

/**
 * Collect form data into API payload
 */
function collectFormData(includeMode = false) {
    const form = document.getElementById('trainingForm');
    const formData = new FormData(form);
    
    // Get checked values for checkbox groups
    const restDays = Array.from(document.querySelectorAll('input[name="rest_days"]:checked'))
        .map(cb => cb.value);
    
    const data = {
        race_type: formData.get('race_type'),
        race_date: formData.get('race_date'),
        race_name: formData.get('race_name') || null,
        goal_time: formData.get('goal_time') || null,
        current_weekly_mileage: parseInt(formData.get('current_weekly_mileage')),
        longest_recent_run: parseInt(formData.get('longest_recent_run')),
        recent_race_times: formData.get('recent_race_times') || null,
        recent_runs: formData.get('recent_runs') || null,
        fitness_level: formData.get('fitness_level'),
        start_date: formData.get('start_date'),
        rest_days: restDays,
        long_run_day: formData.get('long_run_day'),
        double_days_allowed: document.querySelector('input[name="double_days_allowed"]').checked,
        cross_training_days: null,
        running_days_per_week: parseInt(formData.get('running_days_per_week')),
        gym_days_per_week: parseInt(formData.get('gym_days_per_week')),
        years_running: parseInt(formData.get('years_running')),
        previous_injuries: formData.get('previous_injuries') || null,
        previous_experience: formData.get('previous_experience') || null
    };
    
    // Include plan mode if requested (after conflict resolution)
    if (includeMode && selectedPlanMode) {
        data.plan_mode = selectedPlanMode;
        
        // If recommended mode, include the adjusted goal time
        if (selectedPlanMode === 'recommended' && conflictAnalysis?.recommended_goal_time) {
            data.recommended_goal_time = conflictAnalysis.recommended_goal_time;
        }
    }
    
    return data;
}

/**
 * Generate the training plan
 */
async function generatePlan() {
    const formCard = document.getElementById('formCard');
    const planContainer = document.getElementById('planContainer');
    const planOutput = document.getElementById('planOutput');
    const loadingIndicator = document.getElementById('loadingIndicator');
    const progressContainer = document.getElementById('progressContainer');
    
    // Hide form steps, show loading
    document.querySelectorAll('.form-step').forEach(el => el.classList.remove('active'));
    loadingIndicator.classList.add('active');
    document.getElementById('loadingText').textContent = 'Crafting your personalized training plan...';
    
    // Collect data (include mode if we went through conflict resolution)
    const payload = collectFormData(selectedPlanMode !== null);
    
    try {
        // Start streaming request
        const response = await fetch('/api/generate-plan', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(payload)
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to generate plan');
        }
        
        // Hide loading, show plan container
        loadingIndicator.classList.remove('active');
        formCard.style.display = 'none';
        progressContainer.style.display = 'none';
        planContainer.classList.add('active');
        planOutput.textContent = '';
        planOutput.classList.add('cursor-blink');
        generatedPlan = '';
        
        // Read the stream
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        
        while (true) {
            const { done, value } = await reader.read();
            
            if (done) break;
            
            const chunk = decoder.decode(value);
            const lines = chunk.split('\n');
            
            for (const line of lines) {
                if (line.startsWith('data: ')) {
                    try {
                        const data = JSON.parse(line.slice(6));
                        
                        if (data.content) {
                            generatedPlan += data.content;
                            planOutput.textContent = generatedPlan;
                            // Auto-scroll to bottom
                            planOutput.scrollTop = planOutput.scrollHeight;
                        }
                        
                        if (data.done) {
                            planOutput.classList.remove('cursor-blink');
                        }
                        
                        if (data.error) {
                            throw new Error(data.error);
                        }
                    } catch (parseError) {
                        // Ignore parse errors for incomplete chunks
                    }
                }
            }
        }
        
        planOutput.classList.remove('cursor-blink');
        
    } catch (error) {
        console.error('Generation error:', error);
        loadingIndicator.classList.remove('active');
        
        // Show error in plan output
        formCard.style.display = 'none';
        progressContainer.style.display = 'none';
        planContainer.classList.add('active');
        planOutput.textContent = `Error generating plan: ${error.message}\n\nPlease try again or check your API configuration.`;
        planOutput.classList.remove('cursor-blink');
    }
}

/**
 * Copy plan to clipboard
 */
async function copyPlan() {
    try {
        await navigator.clipboard.writeText(generatedPlan);
        showToast('Plan copied to clipboard!');
    } catch (err) {
        // Fallback for older browsers
        const textArea = document.createElement('textarea');
        textArea.value = generatedPlan;
        document.body.appendChild(textArea);
        textArea.select();
        document.execCommand('copy');
        document.body.removeChild(textArea);
        showToast('Plan copied to clipboard!');
    }
}

/**
 * Download plan as text file
 */
function downloadPlan() {
    const blob = new Blob([generatedPlan], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'training-plan.txt';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showToast('Plan downloaded!');
}

/**
 * Print the plan
 */
function printPlan() {
    window.print();
}

/**
 * Start a new plan
 */
function newPlan() {
    const formCard = document.getElementById('formCard');
    const planContainer = document.getElementById('planContainer');
    const progressContainer = document.getElementById('progressContainer');
    
    // Reset state
    generatedPlan = '';
    currentStep = 1;
    conflictAnalysis = null;
    selectedPlanMode = null;
    
    // Show form, hide plan
    planContainer.classList.remove('active');
    formCard.style.display = 'block';
    progressContainer.style.display = 'flex';
    
    // Reset to step 1
    setStep(1);
    
    // Reset form
    document.getElementById('trainingForm').reset();
    initializeDates();
    
    // Reset conflict resolution UI if it exists
    const conflictsList = document.getElementById('conflictsList');
    if (conflictsList) {
        conflictsList.innerHTML = '';
    }
    const generateBtn = document.getElementById('conflictGenerateBtn');
    if (generateBtn) {
        generateBtn.disabled = true;
    }
}

/**
 * Show a temporary toast message
 */
function showToast(message) {
    // Remove existing toast
    const existingToast = document.querySelector('.toast');
    if (existingToast) {
        existingToast.remove();
    }
    
    // Create toast
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    toast.style.cssText = `
        position: fixed;
        bottom: 20px;
        left: 50%;
        transform: translateX(-50%);
        background: var(--bg-card);
        color: var(--text-primary);
        padding: 12px 24px;
        border-radius: var(--radius-md);
        border: 1px solid var(--primary);
        box-shadow: var(--shadow-md);
        z-index: 1000;
        animation: fadeInUp 0.3s ease-out;
    `;
    
    document.body.appendChild(toast);
    
    // Remove after 3 seconds
    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transition = 'opacity 0.3s ease';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}
