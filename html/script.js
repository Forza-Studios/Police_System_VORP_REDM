let currentTargetServerId = null; // tracks the currently open target
let currentSuspectItems = [];
let selectedConfiscateItem = null;

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
        currentTargetServerId = data.targetServerId || null; // store for inventory
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

    // 6. Suspect Satchel Inventory UI
    const invWrapper = document.getElementById('inventory-panel-wrapper');
    if (data.action === 'openSuspectInventory') {
        if (data.targetServerId !== undefined) {
            currentTargetServerId = data.targetServerId;
        }
        const suspectNameEl = document.getElementById('inv-suspect-name');
        const moneyEl = document.getElementById('inv-money-val');
        const goldEl = document.getElementById('inv-gold-val');
        const searchInput = document.getElementById('inv-search-input');

        if (suspectNameEl) suspectNameEl.textContent = data.targetName || 'Unknown Citizen';
        if (moneyEl) moneyEl.textContent = '$' + (Number(data.money || 0).toFixed(2));
        if (goldEl) goldEl.textContent = (Number(data.gold || 0).toFixed(2)) + ' Gold';
        if (searchInput) searchInput.value = '';

        currentSuspectItems = data.items || [];
        renderSuspectItems(currentSuspectItems);

        if (menuWrapper) menuWrapper.classList.add('hidden');
        if (invWrapper) invWrapper.classList.remove('hidden');
    } else if (data.action === 'closeSuspectInventory') {
        if (invWrapper) invWrapper.classList.add('hidden');
        closeConfiscateModal();
    } else if (data.action === 'updateSuspectInventory') {
        if (data.items) {
            currentSuspectItems = data.items;
            renderSuspectItems(currentSuspectItems);
        }
        if (data.money !== undefined) {
            const moneyEl = document.getElementById('inv-money-val');
            if (moneyEl) moneyEl.textContent = '$' + (Number(data.money).toFixed(2));
        }
        if (data.gold !== undefined) {
            const goldEl = document.getElementById('inv-gold-val');
            if (goldEl) goldEl.textContent = (Number(data.gold).toFixed(2)) + ' Gold';
        }
    }

    // 7. Reinforcement Vehicle Menu UI
    const reinforcementWrapper = document.getElementById('reinforcement-menu-wrapper');
    if (data.action === 'openReinforcementMenu') {
        if (data.vehicles) {
            renderReinforcementVehicles(data.vehicles, data.hasActiveVehicle, data.activeVehicleLabel);
        }
        if (reinforcementWrapper) {
            reinforcementWrapper.classList.remove('hidden');
        }
    } else if (data.action === 'closeReinforcementMenu') {
        if (reinforcementWrapper) {
            reinforcementWrapper.classList.add('hidden');
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
    const menuWrapper = document.getElementById('target-menu-wrapper');
    if (menuWrapper) menuWrapper.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/actionSearchInventory`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ targetServerId: currentTargetServerId })
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
        const invWrapper = document.getElementById('inventory-panel-wrapper');
        if (invWrapper && !invWrapper.classList.contains('hidden')) {
            closeInventory();
        }
        const reinforcementWrapper = document.getElementById('reinforcement-menu-wrapper');
        if (reinforcementWrapper && !reinforcementWrapper.classList.contains('hidden')) {
            closeReinforcementMenu();
        }
    }
});

// ==========================================================================
// SUSPECT SATCHEL INVENTORY LOGIC
// ==========================================================================
function closeInventory() {
    const invWrapper = document.getElementById('inventory-panel-wrapper');
    if (invWrapper) invWrapper.classList.add('hidden');
    closeConfiscateModal();
    fetch(`https://${GetParentResourceName()}/closeInventory`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).catch(() => {});
}

const closeInvBtn = document.getElementById('close-inventory-btn');
if (closeInvBtn) {
    closeInvBtn.addEventListener('click', closeInventory);
}

function renderSuspectItems(items) {
    const grid = document.getElementById('inv-items-grid');
    const countEl = document.getElementById('inv-item-count');
    if (!grid) return;

    const query = (document.getElementById('inv-search-input')?.value || '').trim().toLowerCase();
    const filtered = (items || []).filter(item => {
        if (!query) return true;
        const name = (item.name || '').toLowerCase();
        const label = (item.label || '').toLowerCase();
        return name.includes(query) || label.includes(query);
    });

    if (countEl) {
        const totalUnique = (items || []).length;
        countEl.textContent = `${totalUnique} item${totalUnique === 1 ? '' : 's'}`;
    }

    if (!filtered || filtered.length === 0) {
        grid.innerHTML = `
            <div class="inv-empty-state">
                <svg viewBox="0 0 24 24" fill="currentColor">
                    <path d="M20 6h-4V4c0-1.11-.89-2-2-2h-4c-1.11 0-2 .89-2 2v2H4c-1.11 0-1.99.89-1.99 2L2 19c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-6 0h-4V4h4v2z"/>
                </svg>
                <span>${query ? 'No matching items in satchel' : 'Satchel appears empty...'}</span>
            </div>
        `;
        return;
    }

    let html = '';
    filtered.forEach(item => {
        const itemName = escapeHtml(item.name || 'item');
        const itemLabel = escapeHtml(item.label || item.name || 'Unknown Item');
        const count = item.count || 1;
        const imgSrc = `nui://vorp_inventory/html/img/items/${item.name}.png`;

        html += `
            <div class="inv-item-card" data-name="${itemName}">
                <div class="inv-item-left">
                    <div class="inv-item-icon-box">
                        <img src="${imgSrc}" alt="${itemLabel}" onerror="this.onerror=null; this.src='https://cfx-nui-vorp_inventory/html/img/items/${item.name}.png'; this.addEventListener('error', () => { this.style.display='none'; this.nextElementSibling.style.display='block'; });" />
                        <svg class="inv-fallback-svg" viewBox="0 0 24 24" fill="currentColor" style="display:none;">
                            <path d="M20 6h-4V4c0-1.11-.89-2-2-2h-4c-1.11 0-2 .89-2 2v2H4c-1.11 0-1.99.89-1.99 2L2 19c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-6 0h-4V4h4v2z"/>
                        </svg>
                    </div>
                    <div class="inv-item-text">
                        <span class="inv-item-label" title="${itemLabel}">${itemLabel}</span>
                        <span class="inv-item-qty">Qty: ${count}</span>
                    </div>
                </div>
                <button type="button" class="btn-seize-item" onclick="promptConfiscateItem('${itemName}', '${itemLabel.replace(/'/g, "\\'")}', ${count})">
                    Seize
                </button>
            </div>
        `;
    });

    grid.innerHTML = html;
}

// Search Filter Input Listener
const searchInput = document.getElementById('inv-search-input');
if (searchInput) {
    searchInput.addEventListener('input', function() {
        renderSuspectItems(currentSuspectItems);
    });
}

// Seizure / Confiscate Sub-Modal Logic
function promptConfiscateItem(name, label, maxCount) {
    selectedConfiscateItem = { name: name, label: label, maxCount: maxCount };

    const modal = document.getElementById('confiscate-submodal');
    const titleEl = document.getElementById('confiscate-item-title');
    const inputEl = document.getElementById('confiscate-amount-input');

    if (titleEl) titleEl.textContent = label;
    if (inputEl) {
        inputEl.max = maxCount;
        inputEl.value = 1;
    }

    if (modal) modal.classList.remove('hidden');
}

function closeConfiscateModal() {
    const modal = document.getElementById('confiscate-submodal');
    if (modal) modal.classList.add('hidden');
    selectedConfiscateItem = null;
}

const cancelConfiscateBtn = document.getElementById('btn-cancel-confiscate');
if (cancelConfiscateBtn) {
    cancelConfiscateBtn.addEventListener('click', closeConfiscateModal);
}

const maxConfiscateBtn = document.getElementById('confiscate-max-btn');
if (maxConfiscateBtn) {
    maxConfiscateBtn.addEventListener('click', function() {
        if (!selectedConfiscateItem) return;
        const inputEl = document.getElementById('confiscate-amount-input');
        if (inputEl) inputEl.value = selectedConfiscateItem.maxCount;
    });
}

const confirmConfiscateBtn = document.getElementById('btn-confirm-confiscate');
if (confirmConfiscateBtn) {
    confirmConfiscateBtn.addEventListener('click', function() {
        if (!selectedConfiscateItem) return;

        const inputEl = document.getElementById('confiscate-amount-input');
        let amount = parseInt(inputEl ? inputEl.value : 1, 10);
        if (isNaN(amount) || amount < 1) amount = 1;
        if (amount > selectedConfiscateItem.maxCount) amount = selectedConfiscateItem.maxCount;

        fetch(`https://${GetParentResourceName()}/actionConfiscateItem`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                targetServerId: currentTargetServerId,
                itemName: selectedConfiscateItem.name,
                itemLabel: selectedConfiscateItem.label,
                count: amount
            })
        }).catch(() => {});

        closeConfiscateModal();
    });
}

// ==========================================================================
// REINFORCEMENT VEHICLE MENU LOGIC
// ==========================================================================
function closeReinforcementMenu() {
    const wrapper = document.getElementById('reinforcement-menu-wrapper');
    if (wrapper) wrapper.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/closeReinforcementMenu`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).catch(() => {});
}

const closeReinforcementBtn = document.getElementById('close-reinforcement-btn');
if (closeReinforcementBtn) {
    closeReinforcementBtn.addEventListener('click', closeReinforcementMenu);
}

function renderReinforcementVehicles(vehicles, hasActiveVehicle, activeVehicleLabel) {
    const grid = document.getElementById('reinforcement-vehicles-grid');
    if (!grid) return;

    if (!vehicles || vehicles.length === 0) {
        grid.innerHTML = `
            <div class="reinforcement-empty-state">
                <p>No reinforcement vehicles available.</p>
            </div>
        `;
        return;
    }

    let html = '';

    // Active vehicle return banner
    if (hasActiveVehicle) {
        const activeName = escapeHtml(activeVehicleLabel || 'Unknown Vehicle');
        html += `
            <div class="reinforcement-active-banner">
                <div class="active-banner-left">
                    <svg viewBox="0 0 24 24" fill="currentColor" class="active-banner-icon">
                        <path d="M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.5 16c-.83 0-1.5-.67-1.5-1.5S5.67 13 6.5 13s1.5.67 1.5 1.5S7.33 16 6.5 16zm11 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zM5 11l1.5-4.5h11L19 11H5z"/>
                    </svg>
                    <div class="active-banner-info">
                        <span class="active-banner-label">DEPLOYED VEHICLE</span>
                        <span class="active-banner-name">${activeName}</span>
                    </div>
                </div>
                <button type="button" class="btn-return-vehicle" onclick="returnReinforcement()">
                    <svg viewBox="0 0 24 24" fill="currentColor">
                        <path d="M19 7v4H5.83l3.58-3.59L8 6l-6 6 6 6 1.41-1.41L5.83 13H21V7z"/>
                    </svg>
                    Return to Depot
                </button>
            </div>
        `;
    }

    vehicles.forEach(vehicle => {
        const label = escapeHtml(vehicle.label || 'Unknown Vehicle');
        const model = escapeHtml(vehicle.model || '');
        const desc = escapeHtml(vehicle.desc || '');
        const imgSrc = vehicle.image ? `img/${vehicle.image}` : '';

        html += `
            <div class="reinforcement-vehicle-card">
                <div class="vehicle-image-wrap">
                    ${imgSrc ? `<img src="${imgSrc}" alt="${label}" class="vehicle-image" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';" />` : ''}
                    <div class="vehicle-image-fallback" ${imgSrc ? 'style="display:none;"' : ''}>
                        <svg viewBox="0 0 24 24" fill="currentColor">
                            <path d="M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.5 16c-.83 0-1.5-.67-1.5-1.5S5.67 13 6.5 13s1.5.67 1.5 1.5S7.33 16 6.5 16zm11 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zM5 11l1.5-4.5h11L19 11H5z"/>
                        </svg>
                    </div>
                    <div class="vehicle-image-overlay"></div>
                </div>
                <div class="vehicle-info">
                    <h3 class="vehicle-label">${label}</h3>
                    <span class="vehicle-model">${model}</span>
                    ${desc ? `<p class="vehicle-desc">${desc}</p>` : ''}
                </div>
                <button type="button" class="btn-request-vehicle" onclick="requestReinforcement('${model}', '${label.replace(/'/g, "\\\'")}')">
                    <svg viewBox="0 0 24 24" fill="currentColor">
                        <path d="M12 2l2.4 7.2h7.6l-6 4.8 2.4 7.2-6.4-4.8-6.4 4.8 2.4-7.2-6-4.8h7.6z"/>
                    </svg>
                    Request Vehicle
                </button>
            </div>
        `;
    });

    grid.innerHTML = html;
}

function requestReinforcement(model, label) {
    fetch(`https://${GetParentResourceName()}/spawnReinforcement`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ model: model, label: label })
    }).catch(() => {});

    // Close the menu after requesting
    const wrapper = document.getElementById('reinforcement-menu-wrapper');
    if (wrapper) wrapper.classList.add('hidden');
}

function returnReinforcement() {
    fetch(`https://${GetParentResourceName()}/returnReinforcement`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).catch(() => {});

    // Close the menu after returning
    const wrapper = document.getElementById('reinforcement-menu-wrapper');
    if (wrapper) wrapper.classList.add('hidden');
}
