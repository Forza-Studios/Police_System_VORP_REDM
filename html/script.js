window.addEventListener('message', function(event) {
    const data = event.data;

    // 1. Duty Pill UI
    const dutyContainer = document.getElementById('duty-pill-container');
    const dutyText = document.getElementById('duty-text');

    if (data.action === 'showDutyPill') {
        if (data.text) {
            dutyText.textContent = data.text;
        }
        dutyContainer.classList.remove('hidden');
    } else if (data.action === 'hideDutyPill') {
        dutyContainer.classList.add('hidden');
    }

    // 2. Target Action Menu Modal UI
    const menuWrapper = document.getElementById('target-menu-wrapper');
    const targetName = document.getElementById('target-name');
    const targetStatus = document.getElementById('target-status');
    const cuffLabel = document.getElementById('cuff-action-label');

    if (data.action === 'openTargetMenu') {
        if (data.targetName) {
            targetName.textContent = data.targetName;
        }

        if (data.isCuffed) {
            targetStatus.textContent = 'Handcuffed';
            targetStatus.className = 'status-badge cuffed';
            cuffLabel.textContent = 'Uncuff Individual';
        } else {
            targetStatus.textContent = 'Uncuffed';
            targetStatus.className = 'status-badge uncuffed';
            cuffLabel.textContent = 'Handcuff Individual';
        }

        const carryBtn = document.getElementById('btn-carry');
        const carryLabel = document.getElementById('carry-action-label');

        if (data.isCuffed) {
            carryBtn.style.display = 'flex';
            if (data.isCarrying) {
                carryLabel.textContent = 'Drop Individual';
            } else {
                carryLabel.textContent = 'Carry / Escort';
            }
        } else {
            carryBtn.style.display = 'none';
        }

        menuWrapper.classList.remove('hidden');
    } else if (data.action === 'closeTargetMenu') {
        menuWrapper.classList.add('hidden');
    }

    // 3. Alert Panel UI
    const alertWrapper = document.getElementById('alert-panel-wrapper');
    if (data.action === 'openAlertPanel') {
        // Reset the Call Sheriff button state when opening
        const sheriffBtn = document.getElementById('btn-call-sheriff');
        if (sheriffBtn) {
            sheriffBtn.classList.remove('call-sent');
            sheriffBtn.classList.add('active');
            const nameEl = sheriffBtn.querySelector('.service-name');
            const descEl = sheriffBtn.querySelector('.service-desc');
            if (nameEl) nameEl.textContent = 'Call Sheriff';
            if (descEl) descEl.textContent = 'Request law enforcement to your location';
        }
        alertWrapper.classList.remove('hidden');
    } else if (data.action === 'closeAlertPanel') {
        alertWrapper.classList.add('hidden');
    }

    // 4. Incoming Call Alert Pill (shown to on-duty sheriffs)
    const callAlertContainer = document.getElementById('call-alert-pill-container');
    const callAlertText = document.getElementById('call-alert-text');

    if (data.action === 'showCallAlert') {
        if (data.text) {
            callAlertText.textContent = data.text;
        }
        callAlertContainer.classList.remove('hidden');

        // Auto-hide after duration (default 10s)
        const duration = data.duration || 10000;
        if (window._callAlertTimeout) {
            clearTimeout(window._callAlertTimeout);
        }
        window._callAlertTimeout = setTimeout(function() {
            callAlertContainer.classList.add('hidden');
        }, duration);
    } else if (data.action === 'hideCallAlert') {
        callAlertContainer.classList.add('hidden');
        if (window._callAlertTimeout) {
            clearTimeout(window._callAlertTimeout);
            window._callAlertTimeout = null;
        }
    }

    // 5. Sheriff Dashboard UI (Opened via /sheriff)
    const dashWrapper = document.getElementById('sheriff-dashboard-wrapper');
    const officerNameEl = document.getElementById('dash-officer-name');

    if (data.action === 'openSheriffDashboard') {
        if (data.officerName && officerNameEl) {
            officerNameEl.textContent = data.officerName;
        }
        if (data.activeCalls) {
            renderActiveCalls(data.activeCalls);
        }
        if (data.doorStates) {
            updateDoorStates(data.doorStates);
        }
        if (dashWrapper) {
            dashWrapper.classList.remove('hidden');
        }
    } else if (data.action === 'closeSheriffDashboard') {
        if (dashWrapper) {
            dashWrapper.classList.add('hidden');
        }
    } else if (data.action === 'updateActiveCalls') {
        if (data.activeCalls) {
            renderActiveCalls(data.activeCalls);
        }
    }
});

function escapeHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

function renderActiveCalls(calls) {
    const container = document.getElementById('active-calls-list');
    const countBadge = document.getElementById('calls-badge-count');

    if (!container) return;

    if (!calls || calls.length === 0) {
        if (countBadge) countBadge.textContent = '0';
        container.innerHTML = `
            <div class="empty-calls-state">
                <div class="empty-stamp">VALENTINE SHERIFF</div>
                <p>No active distress calls or telegrams logged in county records.</p>
            </div>
        `;
        return;
    }

    if (countBadge) countBadge.textContent = calls.length.toString();
    let html = '';

    calls.forEach(call => {
        const isResponded = call.status === 'RESPONDED';
        const statusText = isResponded ? 'OFFICER RESPONDING' : 'PENDING ASSISTANCE';
        const statusClass = isResponded ? 'responded' : 'pending';
        const cx = call.coords ? call.coords.x.toFixed(1) : '0';
        const cy = call.coords ? call.coords.y.toFixed(1) : '0';
        const rawX = call.coords ? call.coords.x : 0;
        const rawY = call.coords ? call.coords.y : 0;
        const rawZ = call.coords ? call.coords.z : 0;

        html += `
            <div class="call-card" data-id="${call.id}">
                <div class="call-left">
                    <div class="call-icon-wrap">
                        <svg viewBox="0 0 24 24" fill="currentColor">
                            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/>
                        </svg>
                    </div>
                    <div class="call-info">
                        <div class="call-caller">${escapeHtml(call.callerName || 'Unknown Citizen')} (ID: ${call.callerSrc || '?'})</div>
                        <div class="call-details">Distress Signal Reported • Coords: (${cx}, ${cy})</div>
                        <div class="call-meta">
                            <span>Logged: ${call.timeStr || 'Recent'}</span>
                            <span class="call-status-tag ${statusClass}">${statusText}</span>
                        </div>
                    </div>
                </div>
                <div class="call-actions">
                    <button class="btn-waypoint" onclick="setCallWaypoint(${rawX}, ${rawY}, ${rawZ}, ${call.id})">
                        <svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
                        Set Waypoint
                    </button>
                    ${!isResponded ? `<button class="btn-respond" onclick="respondToCall(${call.id})">Respond</button>` : ''}
                    <button class="btn-resolve" onclick="resolveCall(${call.id})">Clear</button>
                </div>
            </div>
        `;
    });

    container.innerHTML = html;
}

function updateDoorStates(doorStates) {
    if (!doorStates) return;
    // Update Cell 1 & Cell 2 UI status if matching hashes are found
    const cell1El = document.getElementById('cell-1-lock-status');
    const cell2El = document.getElementById('cell-2-lock-status');
    if (cell1El) {
        cell1El.textContent = 'LOCKED';
        cell1El.className = 'status-value locked';
    }
    if (cell2El) {
        cell2El.textContent = 'LOCKED';
        cell2El.className = 'status-value locked';
    }
}

function closeSheriffDashboard() {
    const dashWrapper = document.getElementById('sheriff-dashboard-wrapper');
    if (dashWrapper) dashWrapper.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/closeSheriffDashboard`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

const closeDashBtn = document.getElementById('close-dashboard-btn');
if (closeDashBtn) {
    closeDashBtn.addEventListener('click', closeSheriffDashboard);
}

function setCallWaypoint(x, y, z, callId) {
    fetch(`https://${GetParentResourceName()}/setCallWaypoint`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ x: x, y: y, z: z, callId: callId })
    }).catch(() => {});
}

function respondToCall(callId) {
    fetch(`https://${GetParentResourceName()}/respondCall`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ callId: callId })
    }).catch(() => {});
}

function resolveCall(callId) {
    fetch(`https://${GetParentResourceName()}/resolveCall`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ callId: callId })
    }).catch(() => {});
}

// Tab Switching Navigation
document.querySelectorAll('.dash-tab').forEach(tabBtn => {
    tabBtn.addEventListener('click', function() {
        const targetTabId = this.getAttribute('data-tab');

        document.querySelectorAll('.dash-tab').forEach(btn => btn.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));

        this.classList.add('active');
        const targetContent = document.getElementById(targetTabId);
        if (targetContent) {
            targetContent.classList.add('active');
        }
    });
});

function closeMenu() {
    const menuWrapper = document.getElementById('target-menu-wrapper');
    menuWrapper.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/closeMenu`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

document.getElementById('close-menu-btn').addEventListener('click', closeMenu);

function closeAlertPanel() {
    const alertWrapper = document.getElementById('alert-panel-wrapper');
    alertWrapper.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/closeAlertPanel`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

document.getElementById('close-alert-btn').addEventListener('click', closeAlertPanel);

// Call Sheriff Button
document.getElementById('btn-call-sheriff').addEventListener('click', function() {
    const btn = this;

    // Prevent double-clicks
    if (btn.classList.contains('call-sent')) return;

    // Send the NUI callback to client.lua
    fetch(`https://${GetParentResourceName()}/actionCallSheriff`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });

    // Visual feedback: show "call sent" state
    btn.classList.remove('active');
    btn.classList.add('call-sent');
    const nameEl = btn.querySelector('.service-name');
    const descEl = btn.querySelector('.service-desc');
    if (nameEl) nameEl.textContent = 'Call Sent!';
    if (descEl) descEl.textContent = 'Sheriff has been notified of your location';

    // Close the panel after a short delay
    setTimeout(function() {
        closeAlertPanel();
    }, 1500);
});

document.getElementById('btn-handcuff').addEventListener('click', function() {
    const menuWrapper = document.getElementById('target-menu-wrapper');
    menuWrapper.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/actionHandcuff`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
});

document.getElementById('btn-carry').addEventListener('click', function() {
    const menuWrapper = document.getElementById('target-menu-wrapper');
    menuWrapper.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/actionCarry`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
});

document.getElementById('btn-show-id').addEventListener('click', function() {
    fetch(`https://${GetParentResourceName()}/actionComingSoon`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ msg: 'Show ID feature coming soon!' })
    });
});

document.getElementById('btn-open-inventory').addEventListener('click', function() {
    fetch(`https://${GetParentResourceName()}/actionComingSoon`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ msg: 'Open Inventory feature coming soon!' })
    });
});

document.getElementById('btn-put-jail').addEventListener('click', function() {
    const menuWrapper = document.getElementById('target-menu-wrapper');
    menuWrapper.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/actionPutInJail`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
});

document.addEventListener('keyup', function(event) {
    if (event.key === 'Escape' || event.key === 'l' || event.key === 'L') {
        const menuWrapper = document.getElementById('target-menu-wrapper');
        if (menuWrapper && !menuWrapper.classList.contains('hidden')) {
            closeMenu();
        }
    }

    if (event.key === 'Escape') {
        const alertWrapper = document.getElementById('alert-panel-wrapper');
        if (alertWrapper && !alertWrapper.classList.contains('hidden')) {
            closeAlertPanel();
        }
        const dashWrapper = document.getElementById('sheriff-dashboard-wrapper');
        if (dashWrapper && !dashWrapper.classList.contains('hidden')) {
            closeSheriffDashboard();
        }
    }
});


