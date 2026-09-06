window.addEventListener('message', function(event) {
    const data = event.data;
    const container = document.getElementById('duty-pill-container');
    const textElement = document.getElementById('duty-text');

    if (data.action === 'showDutyPill') {
        if (data.text) {
            textElement.textContent = data.text;
        }
        container.classList.remove('hidden');
    } else if (data.action === 'hideDutyPill') {
        container.classList.add('hidden');
    }
});
