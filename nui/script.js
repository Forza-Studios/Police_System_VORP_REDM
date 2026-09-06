var allStaff = [];

// Global Handler for claimStandardKit
function claimStandardKit() {
    $.post('https://gw_policejob/claimStandardKit', JSON.stringify({}));
    if (typeof window.localNotify === 'function') {
        window.localNotify(window._U ? window._U('ui_preparing_kit') : 'ui_preparing_kit', "success");
    }
    $('.hud-equip-trigger').addClass('trigger-active');
    setTimeout(function () { $('.hud-equip-trigger').removeClass('trigger-active'); }, 500);
}
window.claimStandardKit = claimStandardKit;

$(document).ready(function () {
    // Localization Engine
    let UILocales = {};
    let UILang = 'ar';

    window._U = function (key) { return UILocales[key] || key; };

    function translateUI() {
        $('[data-loc]').each(function () {
            let key = $(this).attr('data-loc');
            if (UILocales[key]) {
                $(this).text(UILocales[key]);
            }
        });
        $('[data-loc-placeholder]').each(function () {
            let key = $(this).attr('data-loc-placeholder');
            if (UILocales[key]) {
                $(this).attr('placeholder', UILocales[key]);
            }
        });
        if (UILang === 'en') {
            $('body').attr('dir', 'ltr');
            $('body').addClass('ltr');
        } else {
            $('body').attr('dir', 'rtl');
            $('body').removeClass('ltr');
        }
    }

    function refreshLocales() {
        const resourceName = window.GetParentResourceName ? GetParentResourceName() : 'gw_policejob';
        $.post(`https://${resourceName}/getLocales`, JSON.stringify({}), function (data) {
            UILang = data.lang || 'ar';
            UILocales = data.dict || {};
            translateUI();
        });
    }

    refreshLocales();
    let currentItems = [];

    function loadUIColors(colors) {
        if (!colors) return;
        for (const [key, value] of Object.entries(colors)) {
            document.documentElement.style.setProperty('--' + key, value);
        }
    }

    // Listen for NUI Messages
    window.addEventListener('message', function (event) {
        try {
            let data = event.data;
            if (data.colors) { loadUIColors(data.colors); }

            if (data.action === "openMDT") {
                refreshLocales();
                // Hide other menus
                $('#duty-menu, #interaction-menu, #armory-menu').hide();

                // Ensure main container is visible
                $('#mdt-container').fadeIn(300).css('display', 'flex');

                $('#officerName').text(data.officerName || "CHIEF");
                $('#officerGrade').text(data.grade || "Police");

                updateDutyUI(data.isDuty);
                $('#bossMenuBtn').toggle(data.isBoss);

                if (data.jails) {
                    const container = $('#jailOptionsContainer');
                    container.find('.jail-choice-chip:not([data-value="None"])').remove();
                    data.jails.forEach(jail => {
                        container.append(`<div class="jail-choice-chip" data-value="${jail.value}">${jail.label}</div>`);
                    });
                    $('.jail-choice-chip').off('click').on('click', function () {
                        $('.jail-choice-chip').removeClass('active');
                        $(this).addClass('active');
                        $('#jailLocation').val($(this).data('value'));
                    });
                }

                // Default to dashboard
                $('.nav-btn').removeClass('active');
                $('.nav-btn[data-target="dashboard"]').addClass('active');
                $('.tab-content').removeClass('active');
                $('#dashboard').addClass('active');

                $.post('https://gw_policejob/searchPlayer', JSON.stringify({ query: "" }));
            }

            if (data.action === "searchResults") {
                $('#searchResults').empty();
                if (data.results.length === 0) {
                    $('#searchResults').html('<p style="color:#ef5350;">' + _U('ui_no_results') + '</p>');
                    return;
                }

                data.results.forEach(char => {
                    let statusColor = char.sourceId === "Offline" ? "#ef5350" : "#66bb6a";
                    let statusText = char.sourceId === "Offline" ? "OFFLINE" : "SERVER ID: " + char.sourceId;
                    let charId = char.charIdentifier || char.charidentifier;

                    let html = `
                        <div class="result-card" onclick="viewProfile('${charId}', '${char.firstname}', '${char.lastname}', '${char.rankLabel || char.job}', '${char.sourceId}', '${char.char_img || ""}')">
                            <div style="float:left; font-size:10px; color:${statusColor}; font-weight:bold;">${statusText}</div>
                            <h3>${char.firstname} ${char.lastname}</h3>
                            <p style="color:var(--text-muted); font-size:13px;">${_U('ui_job_prefix')}${char.rankLabel || char.job}</p>
                        </div>
                    `;
                    $('#searchResults').append(html);
                });
            }

            if (data.action === "recordsResults") {
                $('#recordsContainer').empty();
                if (data.records.length === 0) {
                    $('#recordsContainer').html('<p style="color:#ffffff; text-align:center; padding: 20px; font-weight:600;">' + _U('ui_no_history') + '</p>');
                } else {
                    data.records.forEach(rec => {
                        let html = `
                            <div class="record-item">
                                <h4><i class="fas fa-file-lines" style="margin-left:10px;"></i> ${rec.title}</h4>
                                <div class="record-meta">
                                    <i class="fas fa-user-tie"></i> ${_U('ui_issued_by')} ${rec.officer_name} | 
                                    ${_U('ui_date')} ${new Date(rec.date).toLocaleString()}
                                </div>
                                <p>${rec.description}</p>
                                <p><strong class="item-badge">${_U('ui_charges')}</strong> ${rec.charges}</p>
                                <p><strong class="item-badge">${_U('ui_jail_duration')}</strong> ${rec.jail_time} ${_U('ui_time_mins')}</p>
                            </div>
                        `;
                        $('#recordsContainer').append(html);
                    });
                }
                $('#pastRecordsList').fadeIn();
            }

            if (data.action === "warrantsResults") {
                $('#warrantsContainer').empty();
                if (data.warrants.length === 0) {
                    $('#warrantsContainer').html('<p style="color:var(--text-muted); text-align:center;">' + _U('ui_no_active_warrants') + '</p>');
                    return;
                }

                data.warrants.forEach(war => {
                    const defaultImg = "https://i.imgur.com/8K0pX8E.png";
                    let charId = war.charIdentifier || war.charidentifier;
                    let html = `
                        <div class="warrant-item" style="display:flex; gap:20px; align-items:start;">
                            <div class="warrant-img-mini"><img src="${(war.char_img && war.char_img !== 'null') ? war.char_img : defaultImg}"></div>
                            <div style="flex-grow:1;">
                                <h4><i class="fas fa-handcuffs" style="margin-left:10px;"></i> ${_U('ui_warrant_for')} ${war.firstname} ${war.lastname}</h4>
                                <div class="warrant-meta">${_U('ui_issued_by')} ${war.issuer} | ${_U('ui_date')} ${new Date(war.date).toLocaleString()} | ${_U('ui_id')} ${charId}</div>
                                <p>${war.reason}</p>
                                <button class="btn btn-secondary" style="margin-top:10px; width: auto;" onclick="deleteWarrant(${war.id})">${_U('ui_cancel_warrant')}</button>
                            </div>
                        </div>
                    `;
                    $('#warrantsContainer').append(html);
                });
            }

            if (data.action === "updateDispatchMap") {
                /* Map logic disabled per request
                if (typeof map !== 'undefined' && map) {
                    updateLeafletMap(data.cops);
                }
                */

                $('#officersList').empty();
                data.cops.forEach(cop => {
                    let panicClass = cop.isPanic ? 'border: 2px solid #ef5350;' : '';
                    let panicLabel = cop.isPanic ? _U('ui_panic_label') : _U('ui_online');
                    let rankText = cop.rank && cop.rank !== "" ? cop.rank : "Officer";
                    let html = `
                        <div class="result-card" style="${panicClass}" onclick="openMessageDialog(${cop.src}, '${cop.name}')">
                            <h3 style="color:var(--primary-gold); margin-bottom: 5px;">${cop.name}</h3>
                            <div style="display:flex; justify-content:space-between; align-items:center;">
                                <span style="font-size:12px; color:var(--text-muted);">${rankText}</span>
                                <span style="font-size:11px; font-weight:bold; color:${cop.isPanic ? '#ef5350' : '#66bb6a'};">${panicLabel}</span>
                            </div>
                            <p style="font-size:11px; color:#aaa; margin-top:5px;">ID: ${cop.src}</p>
                        </div>
                    `;
                    $('#officersList').append(html);
                });
            }

            if (data.action === "playSound") {
                let sound = new Audio('notification.ogg');
                sound.volume = 0.5; sound.play().catch(e => { });
            }

            if (data.action === "toggleJailTimer") {
                if (data.display) {
                    if (data.name) $('#jailName').text(data.name);
                    $('#jail-timer-overlay').fadeIn(500);
                } else {
                    $('#jail-timer-overlay').fadeOut(500);
                }
            }

            if (data.action === "openArmory") {
                // Ensure a clean state
                $('#mdt-container, #interaction-menu, #duty-menu').hide();
                $('#armory-menu').fadeIn(400).css('display', 'flex');

                // Determine context (Weapons or Vehicles)
                const isVehicles = data.isVehicles || false;

                if (data.officerRank) $('#armoryOfficerRank').text(data.officerRank);
                if (data.officerName) $('#armoryOfficerName').text(data.officerRank + " | " + data.officerName);

                // Populate Assets
                if (isVehicles) {
                    $('.hud-nav-btn[data-target="standardIssueTab"]').hide();
                    $('.hud-nav-btn[data-target="strategicSupportTab"]').addClass('active').show();
                    $('#standardIssueTab').removeClass('active');
                    $('#strategicSupportTab').addClass('active');
                    $('.hud-title-stack h1').text(_U('ui_veh_management'));
                } else {
                    $('.hud-nav-btn[data-target="standardIssueTab"]').addClass('active').show();
                    $('.hud-nav-btn[data-target="strategicSupportTab"]').hide();
                    $('#standardIssueTab').addClass('active');
                    $('#strategicSupportTab').removeClass('active');
                    $('.hud-title-stack h1').text(_U('ui_armory_weapons'));
                }

                // Render specific lists
                if (data.items) renderArmoryItems(data);
                if (data.heavyVehicles) renderHeavyVehicles(data.heavyVehicles, data.gradeId);

                $.post('https://gw_policejob/focusMenu', JSON.stringify({ state: true }));
            }


            if (data.action === "updateJailTimer") {
                $('#jailMin').text(data.minutes < 10 ? "0" + data.minutes : data.minutes);
                $('#jailSec').text(data.seconds < 10 ? "0" + data.seconds : data.seconds);
            }

            if (data.action === "jailedPlayersResults") {
                $('#jailedList').empty();
                if (!data.players || data.players.length === 0) {
                    $('#jailedList').html('<p style="text-align:center; padding:40px; color:var(--text-muted);">' + _U('ui_no_prisoners') + '</p>');
                } else {
                    data.players.forEach(p => {
                        let html = `
                            <div class="result-card">
                                <h3>${p.firstname} ${p.lastname}</h3>
                                <p>${_U('ui_time_remaining')} ${p.jail_time} ${_U('ui_time_mins')}</p>
                                <button class="btn btn-success btn-sm" onclick="unjailPlayer('${p.charidentifier}')">${_U('ui_release')}</button>
                            </div>
                        `;
                        $('#jailedList').append(html);
                    });
                }
            }

            if (data.action === "bossOfficersResults") {
                allStaff = data.players || [];
                renderStaffRoster();
            }

            // --- Interaction Menu & Duty & Armory ---
            if (data.action === "openPoliceMenu") {
                $('#interaction-menu').fadeIn(300);
                currentIntIdx = 0;
                updateIntMenuHighlight();
            }
            if (data.action === "closeMDT") {
                $('#mdt-container').fadeOut(300);
                $.post('https://gw_policejob/closeMenu', JSON.stringify({}));
            }
            if (data.action === "closePoliceMenu") {
                $('#interaction-menu').fadeOut(300);
                $.post('https://gw_policejob/closeMenu', JSON.stringify({}));
            }
            if (data.action === "menuUp") {
                currentIntIdx--;
                if (currentIntIdx < 0) currentIntIdx = intMenuItems.length - 1;
                updateIntMenuHighlight();
            }
            if (data.action === "menuDown") {
                currentIntIdx++;
                if (currentIntIdx >= intMenuItems.length) currentIntIdx = 0;
                updateIntMenuHighlight();
            }
            if (data.action === "menuEnter") {
                $('#' + intMenuItems[currentIntIdx]).click();
            }
            if (data.action === "showNotify") {
                localNotify(data.message, data.type);
            }
            if (data.action === "openDutyMenu") {
                updateDutyUI(data.isDuty);
                $('#mdt-container').hide();
                $('#interaction-menu').hide();
                $('#armory-menu').hide();
                $('#duty-menu').fadeIn(300);
                $.post('https://gw_policejob/focusMenu', JSON.stringify({ state: true }));
            }
            if (data.action === "updateDutyStatus") {
                updateDutyUI(data.isDuty);
            }
            if (data.action === "showPrompt") {
                $('#prompt-title').text(data.title || "OPEN");
                $('#prompt-subtitle').text(data.subtitle || "");
                $('#prompt-key').text(data.key || "G");
                $('#interaction-prompt').fadeIn(200);
            }
            if (data.action === "hidePrompt") {
                $('#interaction-prompt').fadeOut(200);
            }
            if (data.action === "playPromptAnim") {
                $('.prompt-key-box').addClass('prompt-active');
                setTimeout(() => { $('.prompt-key-box').removeClass('prompt-active'); }, 150);
            }
            // [ Duplicate openArmory removed ]

            if (data.action === "closeArmory") {
                closeArmory();
            }
        } catch (err) {
            console.error("[gw_policejob] NUI Error:", err);
        }
    });

    let currentIntIdx = 0;
    let intMenuItems = ['btnSearch', 'btnCuff', 'btnUncuff', 'btnEscort', 'btnPutInVehicle', 'btnTakeOutVehicle', 'btnCheckWanted', 'btnFine', 'btnCloseMenuZ'];

    function updateIntMenuHighlight() {
        $('.interaction-content .menu-btn').removeClass('selected');
        $('#' + intMenuItems[currentIntIdx]).addClass('selected');
    }

    // Nav Helpers and Boss functions
    window.promoteOfficer = function (charid, grade) {
        $.post('https://gw_policejob/manageRank', JSON.stringify({ charid: charid, action: 'promote', currentGrade: grade }));
        setTimeout(() => $.post('https://gw_policejob/getBossOfficers', JSON.stringify({})), 800);
    };
    let pendingFireCharId = null;
    window.fireOfficer = function (charid) {
        pendingFireCharId = charid;
        $('#confirmText').text(_U('notify_confirm_fire'));
        $('#confirmModal').fadeIn(300);
    };

    $('#confirmYes').click(function () {
        if (pendingFireCharId) {
            $.post('https://gw_policejob/manageRank', JSON.stringify({ charid: pendingFireCharId, action: 'fire' }));
            setTimeout(() => $.post('https://gw_policejob/getBossOfficers', JSON.stringify({})), 800);
            pendingFireCharId = null;
        }
        $('#confirmModal').fadeOut(300);
    });

    $('#confirmNo').click(function () {
        pendingFireCharId = null;
        $('#confirmModal').fadeOut(300);
    });
    window.unjailPlayer = function (cid) {
        $.post('https://gw_policejob/unjailPlayer', JSON.stringify({ charid: cid }));
        setTimeout(() => $.post('https://gw_policejob/getJailedPlayers', JSON.stringify({})), 800);
    };
    window.closeArmory = function () {
        $('#armory-menu').fadeOut(300);
        $.post('https://gw_policejob/closeArmoryCallback', JSON.stringify({}));
        $.post('https://gw_policejob/focusMenu', JSON.stringify({ state: false }));
    };

    // Common Buttons
    $('#onDutyBtn').click(() => { $.post('https://gw_policejob/dutyAction', JSON.stringify({ action: 'on' })); $('#duty-menu').hide(); });
    $('#offDutyBtn').click(() => { $.post('https://gw_policejob/dutyAction', JSON.stringify({ action: 'off' })); $('#duty-menu').hide(); });
    $('#closeDutyMenu').click(() => { $('#duty-menu').hide(); $.post('https://gw_policejob/closeMenu', {}); });
    $('#closeArmoryBtn').click(() => closeArmory());
    $('#searchBtn').click(function () {
        const query = $('#searchInput').val().trim();
        $.post('https://gw_policejob/searchPlayer', JSON.stringify({ query: query }));
    });
    $('#panicBtn').click(() => $.post('https://gw_policejob/panicButton', {}));
    $('#btnRefreshJailed').click(() => $.post('https://gw_policejob/getJailedPlayers', JSON.stringify({})));

    // Fine System Listeners
    $('#btnFine').click(function () {
        $('#interaction-menu').hide();
        $('#fine-dialog').fadeIn(300).css('display', 'flex');
        $.post('https://gw_policejob/focusMenu', JSON.stringify({ state: true }));
    });

    $('#submitFineBtn').click(function () {
        const targetId = $('#fineTargetId').val();
        const reason = $('#fineReason').val();
        const amount = $('#fineAmount').val();

        if (!amount || isNaN(amount) || amount <= 0) {
            localNotify(_U('notify_invalid_amount'), "error");
            return
        }

        $.post('https://gw_policejob/giveFine', JSON.stringify({
            targetId: targetId,
            reason: reason,
            amount: amount
        }));

        $('#fine-dialog').fadeOut(300);
        $.post('https://gw_policejob/focusMenu', JSON.stringify({ state: false }));
        // Clear fields
        $('#fineTargetId').val('');
        $('#fineReason').val('');
        $('#fineAmount').val('');
    });

    $('#cancelFineBtn').click(function () {
        $('#fine-dialog').fadeOut(300);
        $.post('https://gw_policejob/closeMenu', JSON.stringify({}));
    });


    // --- INTERACTION MENU CLICK HANDLERS (Missing Logic Restored) ---
    $('#btnSearch').click(function () {
        $.post('https://gw_policejob/actionSearch', JSON.stringify({}));
    });

    $('#btnCuff').click(function () {
        $.post('https://gw_policejob/actionCuff', JSON.stringify({}));
    });

    $('#btnUncuff').click(function () {
        $.post('https://gw_policejob/actionUncuff', JSON.stringify({}));
    });
    $('#btnEscort').click(function () {
        $.post('https://gw_policejob/actionEscort', JSON.stringify({}));
    });
    $('#btnPutInVehicle').click(function () {
        $.post('https://gw_policejob/actionPutInVehicle', JSON.stringify({}));
    });
    $('#btnTakeOutVehicle').click(function () {
        $.post('https://gw_policejob/actionTakeOutVehicle', JSON.stringify({}));
    });
    $('#btnCheckWanted').click(function () {
        $.post('https://gw_policejob/actionCheckWanted', JSON.stringify({}));
    });
    // -------------------------------------------------------------

    $('#btnCloseMenuZ').click(function () {
        $('#interaction-menu').fadeOut(300);
        $.post('https://gw_policejob/closeMenu', JSON.stringify({}));
    });

    function updateDutyUI(isDuty) {
        let badge = $('#duty-badge');
        let text = $('#duty-text');
        if (isDuty) {
            badge.removeClass('status-off').addClass('status-on');
            text.text(_U('ui_on'));
        } else {
            badge.removeClass('status-on').addClass('status-off');
            text.text(_U('ui_off'));
        }
    }

    window.localNotify = function (msg, type) {
        let text = (window._U && typeof window._U === 'function') ? window._U(msg) : msg;
        let n = $(`<div class="custom-notify ${type}">${text}</div>`).appendTo('#notifications-container');
        setTimeout(() => n.fadeOut(400, () => n.remove()), 4000);
    };
    function localNotify(msg, type) {
        window.localNotify(msg, type);
    }

    $(document).on('click', '#claimKitBtn, .hud-equip-trigger', function (e) {
        e.preventDefault();
        window.claimStandardKit();
    });

    function renderArmoryItems(data) {
        let g = $('#weaponGallery').empty();
        let imagePath = data.imagePath || "nui://vorp_inventory/html/img/items/";

        (data.items || []).forEach(item => {
            let img = imagePath + item.id + ".png";
            let typeLabel = item.type === "weapon" ? _U('ui_army_issue') : _U('ui_tactical_item');
            let secondaryLabel = item.type === "weapon" ? `Ammo: ${item.ammo}` : `Count: ${item.count || 1}`;

            let html = `
                <div class="w-card">
                    <img src="${img}" onerror="this.src='https://raw.githubusercontent.com/RexShack/redm-images/main/inventory_items/generic_item.png';">
                    <span class="id-label" style="font-size:7px; opacity:0.5;">${typeLabel}</span>
                    <div class="w-label">${item.name}</div>
                    <div class="w-count">${secondaryLabel}</div>
                </div>
            `;
            g.append(html);
        });
    }

    function renderHeavyVehicles(vhData, playerGrade) {
        let container = $('#heavyVehiclesContainer').empty();

        // Check Rank Restriction
        if (playerGrade < vhData.minRank) {
            container.append(`
                <div class="hud-lock-screen">
                    <i class="fas fa-lock"></i>
                    <h2 data-loc="ui_lock_access">${_U('ui_lock_access')}</h2>
                    <p data-loc="ui_min_rank_req">${_U('ui_min_rank_req', vhData.minRank)}</p>
                </div>
            `);
            return;
        }

        let grid = $('<div class="hud-asset-grid"></div>');
        vhData.list.forEach(vh => {
            let imgStr = vh.image;
            // If the image doesn't start with http or nui, assume it's in our local images/vehicles/
            let finalImg = (imgStr.startsWith('http') || imgStr.startsWith('nui')) ? imgStr : `images/vehicles/${imgStr}`;

            let html = `
                <div class="w-card vh-card">
                    <img src="${finalImg}" onerror="this.src='https://raw.githubusercontent.com/RexShack/redm-images/main/inventory_items/generic_item.png';">
                    <div class="w-label">${_U(vh.name)}</div>
                    <button class="vh-deploy-btn" onclick="spawnHeavyVehicle('${vh.model}')">${_U('ui_request_veh')}</button>
                </div>
            `;
            grid.append(html);
        });
        container.append(grid);

        // Add Global Utility Buttons for Vehicles
        container.append(`
            <div style="width:100%; display:flex; justify-content:center; margin-top:20px; padding-bottom:30px;">
                <button class="vh-delete-btn" style="width:250px; padding:12px;" onclick="deleteNearbyVehicle()">
                    <i class="fas fa-trash-can"></i> ${_U('ui_withdraw_vehs')}
                </button>
            </div>
        `);
    }

    window.spawnHeavyVehicle = function (model) {
        $.post('https://gw_policejob/spawnVehicle', JSON.stringify({ model: model }));
        closeArmory();
        localNotify(_U('notify_veh_en_route'), "success");
    };

    window.deleteNearbyVehicle = function () {
        $.post('https://gw_policejob/deleteStrategicVehicle', JSON.stringify({}));
    };

    // Global Key Handlers (Hardened NUI Input Logic)
    // 1. Force-suppress backspace and escape on elements when typing
    $(document).on('keydown keyup', 'input, textarea', function (e) {
        if (e.which == 27 || e.which == 8) {
            // STOP propagation so window/keyup never sees THIS event while typing
            e.stopPropagation();
            // We allow the browser to handle the event (deletion/default)
            return true;
        }
    });

    // 2. Global Key Listeners
    $(window).on('keydown', function (e) {
        // Esc (27) - Instant close
        if (e.which == 27) {
            // Only close if we aren't focused on an input
            if (!$(e.target).is('input, textarea')) {
                e.preventDefault();
                closeMenus();
            }
        }

        // Backspace (8) - Explicitly prevent browser 'Back' navigation
        if (e.which == 8) {
            if (!$(e.target).is('input, textarea')) {
                e.preventDefault(); // Stop navigation back
            }
        }
    });

    $(window).on('keyup', function (e) {
        // Prevent default on Backspace globally if not in input
        if (e.which == 8 && !$(e.target).is('input, textarea')) {
            e.preventDefault();
        }
    });


    function closeMenus() {
        $('#mdt-container, #interaction-menu, #armory-menu, #duty-menu, #fine-dialog').fadeOut(300);
        $.post('https://gw_policejob/closeMenu', JSON.stringify({}));

        // Cleanup states
        $.post('https://gw_policejob/closeArmoryCallback', JSON.stringify({}));
        $.post('https://gw_policejob/focusMenu', JSON.stringify({ state: false }));
    }

    // Helper for navigation
    $('.hud-nav-btn').click(function () {
        $('.hud-nav-btn').removeClass('active');
        $(this).addClass('active');
        $('.hud-panel').removeClass('active');
        $('#' + $(this).data('target')).addClass('active');
    });

    // MDT Side-Menu Click Handlers
    $('.nav-btn').off('click').on('click', function () {
        const target = $(this).data('target');
        if (!target) return;

        // Tab switching logic
        $('.nav-btn').removeClass('active');
        $(this).addClass('active');
        $('.tab-content').removeClass('active');
        $('#' + target).addClass('active');

        // Special handling for dashboard (auto-search)
        if (target === 'dashboard') {
            $.post('https://gw_policejob/searchPlayer', JSON.stringify({ query: "" }));
        }

        // Refresh jailed list
        if (target === 'jailed-citizens') {
            $.post('https://gw_policejob/getJailedPlayers', JSON.stringify({}));
        }

        // Refresh Warrants list
        if (target === 'warrants') {
            $.post('https://gw_policejob/getWarrants', JSON.stringify({}));
        }

        // Refresh Roster
        if (target === 'roster') {
            $.post('https://gw_policejob/getBossOfficers', JSON.stringify({}));
        }


    });

    // Panic Button in MDT
    $('#panicBtn').click(function () {
        $.post('https://gw_policejob/panicButton', JSON.stringify({}));
        localNotify(_U('notify_panic_sent'), "error");
    });

    // Exit MDT
    $('#closeMDT').click(function () {
        $('#mdt-container').fadeOut(300);
        $.post('https://gw_policejob/closeMDT', JSON.stringify({}));
    });

    // Close MDT
    window.closeMDT = function () {
        $('#mdt-container').fadeOut(300);
        $.post('https://gw_policejob/closeMDT', JSON.stringify({}));
    };

    // Messenger Dialog
    window.openMessageDialog = function (src, name) {
        $('#msgTargetId').val(src);
        $('#msgTargetName').text(name);
        $('#message-dialog').fadeIn(300);
    };

    $('#sendMsgBtn').click(function () {
        let msg = $('#msgContent').val();
        let target = $('#msgTargetId').val();
        if (msg.trim() !== "") {
            $.post('https://gw_policejob/sendMessage', JSON.stringify({ targetId: target, message: msg }));
            $('#message-dialog').fadeOut(300);
            $('#msgContent').val("");
            localNotify(_U('notify_message_sent'), "success");
        }
    });

    $('#cancelMsgBtn').click(() => $('#message-dialog').fadeOut(300));

    // --- CITIZEN PROFILE NAVIGATION (Restored) ---
    window.viewProfile = function (charId, fname, lname, rank, sourceId, charImg) {
        $('#profCharIdentifier').val(charId);
        $('#profFirstName').val(fname);
        $('#profLastName').val(lname);
        $('#profName').text(fname + " " + lname);
        $('#profJob').text(_U('ui_job_prefix') + rank);
        $('#recordServerId').val(sourceId);

        if (charImg && charImg !== "") {
            $('#charImg').attr('src', charImg);
        } else {
            $('#charImg').attr('src', "https://i.imgur.com/8K0pX8E.png");
        }

        // Reset forms
        $('#addRecordForm, #addWarrantForm, #pastRecordsList').hide();
        $('#citizenProfile').fadeIn(300);

        // Fetch Records
        $.post('https://gw_policejob/getRecords', JSON.stringify({ charidentifier: charId }));
    };

    // Button Handlers within Profile
    $('#btnShowAddRecord').click(() => $('#addRecordForm').fadeToggle());
    $('#btnShowAddWarrant').click(() => {
        // Sync suspect image from profile when opening warrant form
        let profileImg = $('#charImg').attr('src');
        if (profileImg && profileImg !== '') {
            $('#warrantSuspectImg').attr('src', profileImg);
            $('#warrantCharImgUrl').val(profileImg !== 'https://i.imgur.com/8K0pX8E.png' ? profileImg : '');
        }
        $('#addWarrantForm').fadeToggle();
    });
    $('#btnViewRecords').click(() => $('#pastRecordsList').fadeToggle());

    $('#submitRecord').click(function () {
        const data = {
            charidentifier: $('#profCharIdentifier').val(),
            targetId: $('#recordServerId').val(),
            title: $('#recordTitle').val(),
            description: $('#recordDesc').val(),
            charges: $('#recordCharges').val(),
            jail_time: $('#jailTime').val(),
            jail_location: $('#jailLocation').val()
        };

        if (data.title === "" || data.charges === "") {
            localNotify(_U('notify_fill_fields'), "error");
            return;
        }

        $.post('https://gw_policejob/addRecord', JSON.stringify(data));
        $('#addRecordForm').hide();
        localNotify(_U('notify_record_saved'), "success");

        // فتح السجل الجنائي فوراً (البيانات ستصل من السيرفر تلقائياً)
        $('#pastRecordsList').fadeIn(400);
    });

    // --- Warrant Photo Update ---
    $('#updateWarrantPhotoBtn').click(function () {
        let url = $('#warrantCharImgUrl').val().trim();
        if (url !== '') {
            $('#warrantSuspectImg').attr('src', url);
            localNotify(_U('notify_photo_updated'), "success");
        } else {
            localNotify(_U('notify_invalid_url'), "error");
        }
    });

    // --- Submit Warrant ---
    $('#submitWarrant').click(function () {
        const charId = $('#profCharIdentifier').val();
        const reason = $('#warrantReason').val().trim();
        const suspectImg = $('#warrantSuspectImg').attr('src');

        if (!charId || charId === '') {
            localNotify(_U('notify_no_suspect'), "error");
            return;
        }
        if (reason === '') {
            localNotify(_U('notify_no_reason'), "error");
            return;
        }

        const data = {
            charidentifier: charId,
            firstname: $('#profFirstName').val(),
            lastname: $('#profLastName').val(),
            reason: reason,
            char_img: suspectImg || ''
        };

        console.log("[gw_policejob] Submitting Warrant:", data);
        $.post('https://gw_policejob/addWarrant', JSON.stringify(data));
        $('#addWarrantForm').hide();
        $('#warrantReason').val('');
        localNotify(_U('notify_warrant_success'), "success");

        // الانتقال التلقائي لتبويب المذكرات
        setTimeout(() => {
            $('.nav-btn').removeClass('active');
            $('.nav-btn[data-target="warrants"]').addClass('active');
            $('.tab-content').removeClass('active');
            $('#warrants').addClass('active');
            // تحديث قائمة المذكرات
            $.post('https://gw_policejob/getWarrants', JSON.stringify({}));
        }, 600);
    });

    // --- Delete Warrant ---
    window.deleteWarrant = function (id) {
        $.post('https://gw_policejob/deleteWarrant', JSON.stringify({ id: id }));
        localNotify(_U('notify_warrant_cancelled'), "success");
        setTimeout(() => $.post('https://gw_policejob/getWarrants', JSON.stringify({})), 800);
    };

    // --- Hire / Rank Management (Manual) ---
    $('#submitHireBtn').click(function () {
        let tSrc = $('#hireTargetSrc').val();
        let tGrade = $('#hireTargetGrade').val();
        if (tSrc !== "" && tGrade !== "") {
            $.post('https://gw_policejob/manageRank', JSON.stringify({ targetSrc: tSrc, action: 'hire', rankGrade: tGrade }));
            localNotify(_U('notify_updating_rank'), "success");
            $('#hireTargetSrc').val("");
            $('#hireTargetGrade').val("");
            setTimeout(() => $.post('https://gw_policejob/getBossOfficers', JSON.stringify({})), 1000);
        } else {
            localNotify(_U('notify_id_rank_required'), "error");
        }
    });

    // --- Staff Search Logic ---
    function renderStaffRoster(filter = "") {
        $('#bossOfficersList').empty();
        const searchTerm = filter.toLowerCase().trim();

        const filteredStaff = allStaff.filter(p => {
            return p.name.toLowerCase().includes(searchTerm) ||
                p.charid.toString().includes(searchTerm);
        });

        if (filteredStaff.length === 0) {
            $('#bossOfficersList').html('<p style="grid-column: 1/-1; text-align:center; padding:40px; color:var(--text-muted);">' + _U('ui_no_results') + '</p>');
            return;
        }

        filteredStaff.forEach(p => {
            let statusColor = p.status === "Online" ? "#66bb6a" : "#ef5350";
            let html = `
                <div class="result-card" style="border-right: 3px solid ${statusColor};">
                    <div style="display:flex; justify-content:space-between; align-items:start;">
                        <div>
                            <h3 style="color:var(--primary-gold); margin:0;">${p.name}</h3>
                            <p style="font-size:12px; color:var(--text-muted); margin:5px 0;">ID: ${p.charid} | ${p.grade}</p>
                        </div>
                        <span style="font-size:10px; font-weight:bold; color:${statusColor};">${p.status.toUpperCase()}</span>
                    </div>
                    <div style="margin-top:15px; display:flex; gap:10px;">
                        <button class="btn btn-gold btn-sm" style="flex:1;" onclick="promoteOfficer('${p.charid}', ${p.gradeId})">
                            <i class="fas fa-arrow-up"></i> ${_U('ui_promote')}
                        </button>
                        <button class="btn btn-danger btn-sm" style="flex:1;" onclick="fireOfficer('${p.charid}')">
                            <i class="fas fa-user-slash"></i> ${_U('ui_fire')}
                        </button>
                    </div>
                </div>
            `;
            $('#bossOfficersList').append(html);
        });
    }

    $('#staffSearchInput').on('input', function () {
        renderStaffRoster($(this).val());
    });

    $('#clearStaffSearch').click(function () {
        $('#staffSearchInput').val('');
        renderStaffRoster('');
    });

});

// ===== SEARCH / FRISK PANEL HANDLER =====
var _searchTargetId = null;
var _searchItems = [];

window.addEventListener('message', function (event) {
    var data = event.data;
    if (!data || !data.action) return;

    if (data.action === 'openSearchPanel') {
        var panel = document.getElementById('searchPanel');
        var nameEl = document.getElementById('searchTargetName');
        var countEl = document.getElementById('searchItemsCount');
        var grid = document.getElementById('searchItemsGrid');
        if (!panel) return;

        _searchTargetId = data.targetId;
        _searchItems = data.items || [];

        nameEl.textContent = data.targetName || '—';
        var imgBase = data.imagePath || 'nui://vorp_inventory/html/img/items/';

        renderSearchItems(grid, countEl, _searchItems, imgBase);
        panel.style.display = 'flex';
    }

    if (data.action === 'closeSearchPanel') {
        var panel = document.getElementById('searchPanel');
        if (panel) panel.style.display = 'none';
        _searchTargetId = null;
        _searchItems = [];
    }

    // Remove item card or update quantity after successful confiscation
    if (data.action === 'removeSearchItem') {
        var card = document.querySelector('[data-item-name="' + data.name + '"]');
        if (card) {
            var itemIndex = _searchItems.findIndex(function (i) { return i.name === data.name; });
            if (itemIndex !== -1) {
                var taken = data.taken || 1;
                var currentAmt = _searchItems[itemIndex].amount || 1;
                var isWeapon = _searchItems[itemIndex].type && _searchItems[itemIndex].type.toLowerCase().indexOf('weapon') !== -1;

                if (currentAmt > taken && !isWeapon) {
                    var newAmt = currentAmt - taken;
                    _searchItems[itemIndex].amount = newAmt;

                    var amountDiv = card.querySelector('.search-item-amount');
                    if (amountDiv) amountDiv.textContent = _U('ui_available') + ' ' + newAmt;

                    var qtyInput = card.querySelector('.search-qty-input');
                    if (qtyInput) {
                        qtyInput.max = newAmt;
                        if (parseInt(qtyInput.value) > newAmt) {
                            qtyInput.value = newAmt;
                        }
                    }
                    return; // Retain card, quantity updated successfully
                } else {
                    _searchItems.splice(itemIndex, 1);
                }
            }

            card.style.transition = 'all 0.3s';
            card.style.opacity = '0';
            card.style.transform = 'scale(0.8)';
            setTimeout(function () {
                card.remove();
                var grid = document.getElementById('searchItemsGrid');
                var remaining = grid ? grid.querySelectorAll('.search-item-card').length : 0;
                var countEl = document.getElementById('searchItemsCount');
                if (countEl) countEl.textContent = remaining > 0 ? remaining + ' ' + _U('ui_tactical_item') : _U('ui_bag_empty');
                if (remaining === 0 && grid) {
                    grid.innerHTML = '<div class="search-empty"><span>✅</span><p>' + _U('notify_confiscated') + '</p></div>';
                }
            }, 300);
        }
    }
});

function renderSearchItems(grid, countEl, items, imgBase) {
    if (!grid) return;
    if (items.length === 0) {
        grid.innerHTML = '<div class="search-empty"><span>📦</span><p>' + _U('ui_bag_empty') + '</p></div>';
        if (countEl) countEl.textContent = _U('ui_bag_empty');
        return;
    }
    if (countEl) countEl.textContent = items.length + ' ' + _U('ui_tactical_item');
    grid.innerHTML = items.map(function (item) {
        var isWeapon = (item.type || '').toLowerCase().indexOf('weapon') !== -1;
        var weaponClass = isWeapon ? 'search-item-weapon' : '';
        var icon = isWeapon ? '🔫' : '📦';
        var imgSrc = (imgBase || '') + item.name + '.png';
        var label = item.label || item.name || '—';
        var amount = item.amount || 1;
        var itemJson = JSON.stringify(item).replace(/'/g, '&#39;');
        var qtyInputHtml = '';
        if (!isWeapon && amount > 1) {
            qtyInputHtml = '<input type="number" id="qty_' + item.name + '" class="search-qty-input" value="1" min="1" max="' + amount + '">';
        }
        return '<div class="search-item-card ' + weaponClass + '" data-item-name="' + item.name + '">' +
            '<img class="search-item-img" src="' + imgSrc + '" ' +
            'onerror="this.style.display=\'none\';this.nextElementSibling.style.display=\'flex\';" ' +
            'onload="this.nextElementSibling.style.display=\'none\';">' +
            '<div class="search-item-img-fallback">' + icon + '</div>' +
            '<div class="search-item-label">' + label + '</div>' +
            '<div class="search-item-amount">' + _U('ui_available') + ' ' + amount + '</div>' +
            qtyInputHtml +
            '<button class="search-take-btn" onclick="confiscateItem(\'' + item.name + '\')" title="' + _U('ui_take_item') + '">⬆ ' + _U('ui_take_item') + '</button>' +
            '</div>';
    }).join('');
}

function confiscateItem(itemName) {
    if (!_searchTargetId) return;
    var item = _searchItems.find(function (i) { return i.name === itemName; });
    if (!item) return;

    var takeQty = item.amount || 1;
    var isWeapon = (item.type || '').toLowerCase().indexOf('weapon') !== -1;

    if (!isWeapon && item.amount > 1) {
        var qtyInput = document.getElementById('qty_' + itemName);
        if (qtyInput) {
            takeQty = parseInt(qtyInput.value) || 1;
            if (takeQty < 1) takeQty = 1;
            if (takeQty > item.amount) takeQty = item.amount;
        }
    }

    var sendItem = JSON.parse(JSON.stringify(item));
    sendItem.takeAmount = takeQty;

    $.post('https://gw_policejob/confiscateItem', JSON.stringify({
        targetId: _searchTargetId,
        item: sendItem
    }));
}

// Close button & ESC for search panel
(function () {
    function closeSearch() {
        var panel = document.getElementById('searchPanel');
        if (panel) panel.style.display = 'none';
        _searchTargetId = null;
        _searchItems = [];
        $.post('https://gw_policejob/closeSearchPanel', JSON.stringify({}));
    }
    document.addEventListener('DOMContentLoaded', function () {
        var btn = document.getElementById('searchCloseBtn');
        if (btn) btn.addEventListener('click', closeSearch);
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape') {
                var p = document.getElementById('searchPanel');
                if (p && p.style.display !== 'none') closeSearch();
            }
        });
    });
})();
