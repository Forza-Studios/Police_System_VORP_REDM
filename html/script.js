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
        alertWrapper.classList.remove('hidden');
    } else if (data.action === 'closeAlertPanel') {
        alertWrapper.classList.add('hidden');
    }
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
        if (!menuWrapper.classList.contains('hidden')) {
            closeMenu();
        }
    }

    if (event.key === 'Escape') {
        const alertWrapper = document.getElementById('alert-panel-wrapper');
        if (!alertWrapper.classList.contains('hidden')) {
            closeAlertPanel();
        }
    }
});
