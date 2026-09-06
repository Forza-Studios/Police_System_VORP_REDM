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

        menuWrapper.classList.remove('hidden');
    } else if (data.action === 'closeTargetMenu') {
        menuWrapper.classList.add('hidden');
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

document.getElementById('btn-handcuff').addEventListener('click', function() {
    const menuWrapper = document.getElementById('target-menu-wrapper');
    menuWrapper.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/actionHandcuff`, {
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
});
