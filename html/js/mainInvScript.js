let imageCache = {};
let activeMainGroupFilter = 'all';
let activeMainGroupFilterTypes = null;
let mainInventoryItemsCache = {};
let mainInventoryLayoutCache = null;
let stopTooltip = false;
let isShiftActive = false;
let altDragActive = false;
let actionsConfigLoaded; // holds the promise once initialized
let invSortTimer = null;
let pendingDropTargetSlot = null;

const MAIN_INVENTORY_SLOT_COLS = 4;
const MAIN_INVENTORY_GRID_ROWS = 5;
const MAIN_INVENTORY_GRID_SLOTS = MAIN_INVENTORY_SLOT_COLS * MAIN_INVENTORY_GRID_ROWS;

const SECOND_INVENTORY_GRID_ROWS = 6;
const SECOND_INVENTORY_GRID_SLOTS = MAIN_INVENTORY_SLOT_COLS * SECOND_INVENTORY_GRID_ROWS;

INVENTORY.MAIN = {
    DROP: {
        MONEY: function (isAll) {
            INVENTORY.DIALOG({ name: "money", id: 0 }, "item_money", "drop", isAll);
        },

        MONEY_ADVANCED: function (isAll) {
            INVENTORY.DIALOG({ name: "money", id: 0 }, "item_money", "dropAdvanced", isAll);
        },

        GOLD: function (isAll) {
            INVENTORY.DIALOG({ name: "gold", id: 0 }, "item_gold", "drop", isAll);
        },

        GOLD_ADVANCED: function (isAll) {
            INVENTORY.DIALOG({ name: "gold", id: 0 }, "item_gold", "dropAdvanced", isAll);
        },

        ROL: function (isAll) {
            INVENTORY.DIALOG({ name: "rol", id: 0 }, "item_rol", "drop", isAll);
        },

        ROL_ADVANCED: function (isAll) {
            INVENTORY.DIALOG({ name: "rol", id: 0 }, "item_rol", "dropAdvanced", isAll);
        },

        ITEM: function (item, isAll, exactQty) {
            if (item && item.type === "item_standard" && exactQty != null && exactQty !== "") {
                const n = parseInt(String(exactQty), 10);
                const cap = parseInt(String(item.count), 10);
                if (Number.isFinite(n) && n > 0 && Number.isFinite(cap) && cap > 0 && n <= cap) {
                    secureCallbackToNui("vorp_inventory", "DropItemStandard", {
                        item: item.name,
                        id: item.id,
                        number: n,
                        metadata: item.metadata,
                        degradation: item.degradation,
                    });
                    return;
                }
            }
            INVENTORY.DIALOG(item, "item_standard", "drop", isAll);
        },

        WEAPON: function (item) {
            secureCallbackToNui("vorp_inventory", "DropItemWeapon", {
                item: item.name,
                hash: item.hash,
                id: parseInt(item.id, 10),
            });
        },

        WEAPON_ADVANCED: function (item) {
            secureCallbackToNui("vorp_inventory", "DropItemAdvanced", {
                item: item.name,
                type: "item_weapon",
                hash: item.hash,
                id: parseInt(item.id, 10),
            });
        },

        ITEM_ADVANCED: function (item, isAll) {
            INVENTORY.DIALOG(item, "item_standard", "dropAdvanced", isAll);
        },
    },

    GIVE: {
        GOLD: function () {
            INVENTORY.DIALOG({ name: "gold", id: 0 }, "item_gold", "give");
        },

        GOLD_AMOUNT: function () {
            const max = UTILS.PARSE_HUD_AMOUNT($("#gold-value"));
            if (!(max > 0)) {
                return;
            }
            dialog.prompt({
                title: LANGUAGE.prompttitle,
                button: LANGUAGE.promptaccept,
                required: true,
                item: "gold",
                type: "item_gold",
                input: {
                    type: "number",
                    autofocus: "true",
                },
                validate: function (value, item, type) {
                    const v = parseFloat(String(value).replace(",", "."));
                    if (!(v > 0)) {
                        dialog.close();
                        return;
                    }
                    if (v > max) {
                        dialog.close();
                        return;
                    }
                    INVENTORY.SEND_GIVE({
                        type: "item_gold",
                        id: 0,
                        count: v,
                    });
                    return true;
                },
            });
        },

        GOLD_ALL: function () {
            const v = UTILS.PARSE_HUD_AMOUNT($("#gold-value"));
            if (!(v > 0)) {
                return;
            }
            INVENTORY.SEND_GIVE({
                type: "item_gold",
                id: 0,
                count: v,
            });
        },

        MONEY: function () {
            INVENTORY.DIALOG({ name: "money", id: 0 }, "item_money", "give");
        },

        MONEY_AMOUNT: function () {
            const max = UTILS.PARSE_HUD_AMOUNT($("#money-value"));
            if (!(max > 0)) {
                return;
            }
            dialog.prompt({
                title: LANGUAGE.prompttitle,
                button: LANGUAGE.promptaccept,
                required: true,
                item: "money",
                type: "item_money",
                input: {
                    type: "number",
                    autofocus: "true",
                },
                validate: function (value, item, type) {
                    const v = parseFloat(String(value).replace(",", "."));
                    if (!(v > 0)) {
                        dialog.close();
                        return;
                    }
                    if (v > max) {
                        dialog.close();
                        return;
                    }
                    INVENTORY.SEND_GIVE({
                        type: "item_money",
                        id: 0,
                        count: v,
                    });
                    return true;
                },
            });
        },

        MONEY_ALL: function () {
            const v = UTILS.PARSE_HUD_AMOUNT($("#money-value"));
            if (!(v > 0)) {
                return;
            }
            INVENTORY.SEND_GIVE({
                type: "item_money",
                id: 0,
                count: v,
            });
        },

        ITEM: function (item) {
            INVENTORY.DIALOG(item, "item_standard", "give");
        },

        ITEM_ALL: function (item) {
            if (!item || item.type !== "item_standard" || !(item.count > 0)) {
                return;
            }
            INVENTORY.SEND_GIVE({
                type: "item_standard",
                item: item.name,
                id: item.id,
                count: item.count,
                metadata: item.metadata,
            });
        },

        WEAPON: function (item) {
            INVENTORY.SEND_GIVE({
                type: "item_weapon",
                item: item.name,
                hash: item.hash,
                id: parseInt(item.id, 10),
            });
        },
        AMMO: function (ammotype) {
            const cap = (allplayerammo && allplayerammo[ammotype] != null)
                ? Number(allplayerammo[ammotype])
                : 0;
            if (!(cap > 0)) {
                return;
            }
            dialog.prompt({
                title: LANGUAGE.prompttitle,
                button: LANGUAGE.promptaccept,
                required: true,
                item: ammotype,
                type: "item_ammo",
                input: {
                    type: "number",
                    autofocus: "true",
                },
                validate: function (value, _itemName, ammoType) {
                    if (!UTILS.IS_INT(value)) {
                        dialog.close();
                        return;
                    }
                    const v = parseInt(value, 10);
                    if (v <= 0 || v > cap) {
                        dialog.close();
                        return;
                    }
                    INVENTORY.SEND_GIVE({
                        type: "item_ammo",
                        item: ammotype,
                        id: 0,
                        count: v,
                    });
                    return true;
                },
            });
        },

        AMMO_ALL: function (ammotype) {
            const cap = (allplayerammo && allplayerammo[ammotype] != null) ? Number(allplayerammo[ammotype]) : 0;
            if (!(cap > 0))
                return;

            INVENTORY.SEND_GIVE({
                type: "item_ammo",
                item: ammotype,
                id: 0,
                count: cap,
            });
        },
    },

    AUTO_SORT: function () {
        const allItems = Object.values(mainInventoryItemsCache);

        allItems.sort(function (a, b) {
            const isWeaponA = a.type === "item_weapon";
            const isWeaponB = b.type === "item_weapon";

            if (isWeaponA !== isWeaponB) {
                if (Config.InvOrder === "items") {
                    return isWeaponA ? 1 : -1; // items first, weapons last
                } else {
                    return isWeaponA ? -1 : 1; // weapons first, items last
                }
            }

            const labelA = (a.custom_label || a.label || a.name || "").toLowerCase();
            const labelB = (b.custom_label || b.label || b.name || "").toLowerCase();
            return labelA.localeCompare(labelB);
        });

        mainInventoryLayoutCache = null;

        INVENTORY.MAIN.INVENTORY_SETUP(allItems, {});
        INVENTORY.MAIN.CLEAR_INV_SORT();
        INVENTORY.MAIN.INIT_INV_SORT();
        INVENTORY.MAIN.QUEUE_LAYOUT_SAVE();
    },

    IS_MAIN_CAT_STRIP: function (container) {
        return !!(container && container.classList && container.classList.contains('mainButton1') && container.closest('.item-groups-rail'));
    },

    IS_CAT_STRIP_SCROLL: function (scrollEl) {
        return INVENTORY.MAIN.IS_MAIN_CAT_STRIP(scrollEl) || INVENTORY.SECONDARY.IS_CATEGORY_STRIP(scrollEl);
    },

    TRIM_EMPTY_TAIL: function (maxSlots) {
        const $inv = $("#inventoryElement");
        if (!$inv.length || maxSlots < 1) return;
        while ($inv.children(".item").length > maxSlots) {
            const $last = $inv.children(".item").last();
            if (!INVENTORY.MAIN.IS_MAIN_EMPTY_SLOT($last)) break;
            $last.remove();
        }
    },

    APPEND_EMPTY_SLOT: function () {
        $("#inventoryElement").append(`<div class="item" data-group="0" data-sortable="true"></div>`);
    },

    EMPTY_FIXED_STRIP: function () {
        $("#inventoryFixedSlotsStrip").empty();
    },

    REPLACE_LEGACY_FIXED_CELLS: function () {
        const $inv = $("#inventoryElement");
        ["#item-money", "#item-gunbelt", "#item-gold", "#item-rol"].forEach(function (sel) {
            $inv.children(sel).each(function () {
                $(this).replaceWith('<div class="item" data-group="0" data-sortable="true"></div>');
            });
        });
    },

    // allows to drag an item and make the inventory scroll up or down
    MAIN_INV_AUTO_SCROLL_DRAG: function (event) {
        const el = document.getElementById("inventoryElement");
        if (!el || el.scrollHeight <= el.clientHeight) return;
        const rect = el.getBoundingClientRect();
        const y = event.clientY ?? event.originalEvent?.clientY;
        const x = event.clientX ?? event.originalEvent?.clientX;
        if (y == null || x == null || x < rect.left || x > rect.right || y < rect.top || y > rect.bottom) return;
        const edgePx = 48;
        let delta = 0;
        if (y < rect.top + edgePx) {
            delta = -Math.ceil(8 + Math.min(1, (rect.top + edgePx - y) / edgePx) * 20);
        } else if (y > rect.bottom - edgePx) {
            delta = Math.ceil(8 + Math.min(1, (y - (rect.bottom - edgePx)) / edgePx) * 20);
        }
        if (delta) el.scrollTop = Math.max(0, Math.min(el.scrollHeight - el.clientHeight, el.scrollTop + delta));
    },

    IS_MAIN_EMPTY_SLOT: function ($el) {
        if (!$el || !$el.length || !$el.is(".item"))
            return false;
        const id = $el.attr("id") || "";
        if (id === "item-money" || id === "item-gunbelt" || id === "item-gold" || id === "item-rol")
            return false;
        const rowItem = $el.data("item");
        if (rowItem && typeof rowItem === "object")
            return false;
        if (rowItem === "money" || rowItem === "gunbelt" || rowItem === "gold" || rowItem === "rol")
            return false;

        return true;
    },

    IS_PAST_SLOT_CAP: function ($cell) {
        if (!$cell || !$cell.length) return false;
        const $inv = $("#inventoryElement");
        if (!$cell.closest("#inventoryElement").length) return false;
        const idx = $inv.children(".item").index($cell);
        return idx >= Config.MainInventoryFixedSlotCount;
    },

    REFRESH_OVERFLOW: function () {
        const $inv = $("#inventoryElement");
        if (!$inv.length) return;

        $inv.children(".item").each(function (i) {
            const $cell = $(this);
            const domId = $cell.attr("id") || "";
            if (domId === "item-money" || domId === "item-gunbelt" || domId === "item-gold" || domId === "item-rol") {
                $cell.removeClass("item--overflow-beyond-slots");
                return;
            }
            const rowItem = $cell.data("item");
            const isPlayerItem = rowItem && typeof rowItem === "object";
            $cell.toggleClass("item--overflow-beyond-slots", i >= Config.MainInventoryFixedSlotCount && !!isPlayerItem);
        });
    },

    IS_POINT_OVER_HOTBAR: function (clientX, clientY) {
        const el = document.getElementById("hotbarHud");
        if (!el) return false;

        const rect = el.getBoundingClientRect();
        return (
            clientX >= rect.left &&
            clientX <= rect.right &&
            clientY >= rect.top &&
            clientY <= rect.bottom
        );
    },

    IS_POINT_IN_MAIN_GRID: function (clientX, clientY) {
        if (clientX == null || clientY == null) return false;
        const inv = document.getElementById("inventoryElement");
        if (!inv) return false;
        const clip = inv.getBoundingClientRect();
        let clipBottom = clip.bottom;
        const hb = document.getElementById("hotbarHud");
        if (hb && !hb.classList.contains("hotbar-hud--hidden")) {
            const hr = hb.getBoundingClientRect();
            if (hr.width > 0 && hr.height > 0) {
                clipBottom = Math.min(clipBottom, hr.top - 4);
            }
        }
        if (clipBottom <= clip.top) return false;
        if (clientX < clip.left || clientX > clip.right || clientY < clip.top || clientY > clipBottom) {
            return false;
        }
        const cells = inv.querySelectorAll(":scope > .item");
        if (!cells.length) {
            return true;
        }
        for (let i = 0; i < cells.length; i++) {
            const r = cells[i].getBoundingClientRect();
            if (r.width <= 0 && r.height <= 0) continue;
            if (r.bottom <= clip.top || r.top >= clipBottom || r.right <= clip.left || r.left >= clip.right) {
                continue;
            }
            if (clientX >= r.left && clientX <= r.right && clientY >= r.top && clientY <= r.bottom) {
                return true;
            }
        }
        return false;
    },

    GET_ITEM_DOM_ID: function (item) {
        const sanitizedItem = (item.type || "").toString().replace(/[^a-zA-Z0-9_-]/g, "_");
        return sanitizedItem + "_" + String(item.id);
    },

    GET_ITEM_SELECTOR: function (domId) {
        const safeDomId = $.escapeSelector ? $.escapeSelector(domId) : domId;
        return "#item-" + safeDomId;
    },

    BIND_H_WHEEL: function (container) {
        if (!container || container.dataset.invWheelBound === "1") return;
        container.dataset.invWheelBound = "1";
        container.addEventListener(
            "wheel",
            function (event) {
                const ay = Math.abs(event.deltaY);
                const ax = Math.abs(event.deltaX);
                const delta = ay > ax ? event.deltaY : event.deltaX;
                if (!delta) return;
                event.preventDefault();
                if (this.id === "carousel1" && this.closest(".item-groups-rail")) {
                    const maxScroll = Math.max(0, this.scrollWidth - this.clientWidth);
                    const next = Math.max(0, Math.min(maxScroll, this.scrollLeft + delta * 0.26));
                    this.scrollLeft = next;
                    return;
                }
                if (this.id === "staticCarousel" && this.closest(".secondary-item-groups")) {
                    const maxScroll = Math.max(0, this.scrollWidth - this.clientWidth);
                    const next = Math.max(0, Math.min(maxScroll, this.scrollLeft + delta * 0.26));
                    this.scrollLeft = next;
                    return;
                }
                this.scrollLeft += delta * 0.26;
            },
            { passive: false }
        );
    },

    IS_ITEM_GROUPS_RAIL: function (carouselEl) {
        return !!(carouselEl && carouselEl.closest && carouselEl.closest('.item-groups-rail'));
    },

    SET_MAIN_GROUP_NAV_TITLE: function (key) {
        const el = document.getElementById("itemGroupsNavTitle");
        if (!el) return;
        el.textContent = UTILS.RESOLVE_ITEM_GROUP_TITLE_TEXT(key);
    },

    STEP_MAIN_GROUP: function (direction) {
        const strip = document.getElementById("carousel1");
        if (!strip) return;
        const buttons = Array.from(strip.querySelectorAll('.dropdownButton[data-type="itemtype"]'));
        if (!buttons.length) return;

        const dir = direction < 0 ? -1 : 1;
        let idx = buttons.findIndex((b) => b.classList && b.classList.contains("active"));
        if (idx < 0) idx = 0;

        let next = idx + dir;
        if (next < 0 || next >= buttons.length) {
            return;
        }

        const target = buttons[next];
        if (!target) return;

        target.click();

        try {
            target.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" });
        } catch (e) {
            // ignore
        }
    },

    TOGGLE_DROPDOWN: function (mainButton) {
        const dropdownButtonsContainers = document.querySelectorAll('.dropdownButtonContainer');
        const itemGroupsAlwaysOpen = 'mainButton1';

        dropdownButtonsContainers.forEach((container) => {
            if (container.classList.contains(mainButton)) {
                let isVisible;
                if (mainButton === itemGroupsAlwaysOpen) {
                    container.classList.add('showDropdown');
                    isVisible = true;
                } else {
                    isVisible = container.classList.toggle('showDropdown');
                }
                const parentCarouselContainer = container.closest('.carouselContainer');
                if (parentCarouselContainer) {
                    const controls = parentCarouselContainer.querySelectorAll('.carousel-control');
                    const isRail = INVENTORY.MAIN.IS_ITEM_GROUPS_RAIL(parentCarouselContainer);
                    controls.forEach(control => {
                        control.style.visibility = isRail ? 'visible' : (isVisible ? 'visible' : 'hidden');
                    });
                }
            } else {
                if (container.classList.contains(itemGroupsAlwaysOpen)) {
                    container.classList.add('showDropdown');
                    const parentKeep = container.closest('.carouselContainer');
                    if (parentKeep) {
                        parentKeep.querySelectorAll('.carousel-control').forEach(control => {
                            control.style.visibility = 'visible';
                        });
                    }
                } else {
                    container.classList.remove('showDropdown');
                    const otherParentCarouselContainer = container.closest('.carouselContainer');
                    if (otherParentCarouselContainer) {
                        const controls = otherParentCarouselContainer.querySelectorAll('.carousel-control');
                        controls.forEach(control => control.style.visibility = 'hidden');
                    }
                }
            }
        });

        const dropdownContainers = document.querySelectorAll('.dropdownButtonContainer');
        dropdownContainers.forEach(bindHorizontalWheelScroll);
    },

    INIT_STATIC_CAROUSEL: function () {
        const staticDropdownContainer = document.querySelector('#staticCarousel');
        if (staticDropdownContainer) {
            INVENTORY.MAIN.BIND_H_WHEEL(staticDropdownContainer);
        }
    },

    SCROLL_CAROUSEL: function (carouselId, direction) {
        const container = document.getElementById(carouselId);
        if (!container) {
            return;
        }
        var scrollAmount = 200;
        if ((carouselId === 'carousel1' || carouselId === 'staticCarousel') && container.clientWidth > 0) {
            scrollAmount = Math.max(56, Math.round(container.clientWidth / 8));
        }
        container.scrollBy({ left: direction * scrollAmount, behavior: 'smooth' });
        if (INVENTORY.MAIN.IS_CAT_STRIP_SCROLL(container)) {
            requestAnimationFrame(() => INVENTORY.MAIN.CLAMP_CAT_STRIP(container));
            setTimeout(() => INVENTORY.MAIN.CLAMP_CAT_STRIP(container), 140);
            setTimeout(() => INVENTORY.MAIN.CLAMP_CAT_STRIP(container), 380);
        }
    },

    LOAD_ACTIONS_CONFIG: function () {
        if (!actionsConfigLoaded) {
            actionsConfigLoaded = new Promise((resolve, reject) => {
                fetch(`https://${GetParentResourceName()}/getActionsConfig`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json; charset=UTF-8',
                    }
                })
                    .then(response => response.json())
                    .then(actionsConfig => {
                        window.ITEM_GROUPS = actionsConfig;
                        resolve(actionsConfig);
                    })
                    .catch(error => {
                        reject(error);
                    });
            });
        }
        return actionsConfigLoaded;
    },

    SCHEDULE_MAIN_GROUP_STRIP: function () {
        const container = document.getElementById('carousel1');
        if (!container) {
            return;
        }

        container.style.scrollBehavior = 'auto';
        container.style.width = '';
        container.style.minWidth = '';
        container.style.maxWidth = '';
        container.style.flexBasis = '';
        container.scrollLeft = 0;

        requestAnimationFrame(() => INVENTORY.MAIN.CLAMP_CAT_STRIP(container));
        setTimeout(() => {
            const c = document.getElementById('carousel1');
            if (c) {
                c.style.scrollBehavior = 'auto';
                INVENTORY.MAIN.CLAMP_CAT_STRIP(c);
            }
        }, 450);
    },

    CLAMP_CAT_STRIP: function (scrollEl) {
        if (!INVENTORY.MAIN.IS_CAT_STRIP_SCROLL(scrollEl)) {
            return;
        }
        void scrollEl.offsetHeight;

        const roam = scrollEl.scrollWidth - scrollEl.clientWidth;
        const rawMax = Math.max(0, roam);
        const sl = scrollEl.scrollLeft;

        if (sl < 0) {
            scrollEl.scrollLeft = 0;
        } else if (sl > rawMax + 0.5) {
            scrollEl.scrollLeft = rawMax;
        }
    },

    BIND_CAT_STRIP_CLAMP: function (container) {
        if (!INVENTORY.MAIN.IS_CAT_STRIP_SCROLL(container) || container.dataset.groupsScrollClamp === '1') {
            return;
        }
        container.dataset.groupsScrollClamp = '1';
        let clampTimer = 0;
        const tick = () => INVENTORY.MAIN.CLAMP_CAT_STRIP(container);
        container.addEventListener('scroll', () => {
            tick();
            clearTimeout(clampTimer);
            clampTimer = setTimeout(tick, 130);
        }, { passive: true });
    },

    GEN_ACTION_BUTTONS: function (actionsConfig, containerId, inventoryContext, buttonClass) {
        const basePath = "img/itemtypes/";
        const container = document.getElementById(containerId);

        if (container) {
            Object.keys(actionsConfig).forEach(key => {
                const action = actionsConfig[key];
                const button = document.createElement('button');
                button.className = buttonClass;
                button.type = 'button';
                button.setAttribute('data-type', 'itemtype');
                button.setAttribute('data-param', key);
                button.setAttribute('data-label', (action && action.label) ? String(action.label) : "");
                button.setAttribute('data-desc', "");
                button.setAttribute('onclick', `INVENTORY.MAIN.GROUP_FILTER_ACTION('itemtype', '${key}', '${inventoryContext}')`);

                const div = document.createElement('div');
                const img = document.createElement('img');
                img.src = basePath + action.img;
                img.alt = "Image";
                div.appendChild(img);
                button.appendChild(div);
                container.appendChild(button);
            });

            INVENTORY.MAIN.BIND_H_WHEEL(container);

            if (container.classList.contains('mainButton1') && container.closest('.item-groups-rail')) {
                container.classList.add('showDropdown');
                INVENTORY.MAIN.BIND_CAT_STRIP_CLAMP(container);
                INVENTORY.MAIN.SCHEDULE_MAIN_GROUP_STRIP();
                const pc = container.closest('.carouselContainer');
                if (pc) {
                    pc.querySelectorAll('.carousel-control').forEach(ctrl => {
                        ctrl.style.visibility = 'visible';
                    });
                }
            } else if (containerId === 'staticCarousel' && container.closest('.secondary-item-groups')) {
                INVENTORY.MAIN.BIND_CAT_STRIP_CLAMP(container);
                INVENTORY.SECONDARY.SCHEDULE_GROUP_STRIP();
            }
        } else {
            console.warn(`Container for action buttons not found: ${containerId}`);
        }
    },

    GROUP_FILTER_ACTION: function (type, param, inv) {
        if (type === 'itemtype') {
            if (inv === "inventoryElement") {
                document.querySelectorAll('.dropdownButton[data-type="itemtype"]').forEach(btn => btn.classList.remove('active'));
                const activeButtonMain = document.querySelector(`.dropdownButton[data-param="${param}"][data-type="itemtype"]`);
                if (activeButtonMain)
                    activeButtonMain.classList.add('active');
            } else if (inv === "secondInventoryElement") {
                document.querySelectorAll('.dropdownButton1').forEach(btn => {
                    if (btn.getAttribute('data-type') === 'itemtype')
                        btn.classList.remove('active');
                });

                const activeButtonSecond = document.querySelector(`.dropdownButton1[data-param="${param}"][data-type="itemtype"]`);
                if (activeButtonSecond)
                    activeButtonSecond.classList.add('active');
            }
            let resolvedKey = param;
            let resolvedTypes;
            if (param in ITEM_GROUPS) {
                resolvedTypes = ITEM_GROUPS[param].types;
            } else {
                resolvedKey = 'all';
                resolvedTypes = ITEM_GROUPS['all'].types;
            }

            if (inv === "inventoryElement") {
                INVENTORY.MAIN.APPLY_MAIN_GROUP_FILTER(resolvedKey, resolvedTypes);
                INVENTORY.MAIN.SET_MAIN_GROUP_NAV_TITLE(resolvedKey);
            } else {
                INVENTORY.MAIN.SHOW_ITEMS_BY_TYPE(resolvedTypes, inv);
                INVENTORY.SECONDARY.SET_GROUP_NAV_TITLE(resolvedKey);
            }
        }
    },

    SHOW_ITEMS_BY_TYPE: function (itemTypesToShow, inv) {
        let itemDiv = 0;
        let itemEmpty = 0;
        $(`#${inv} .item`).each(function () {
            const group = $(this).data("group");

            if (itemTypesToShow.length === 0 || itemTypesToShow.includes(group)) {
                if (group != 0) {
                    itemDiv = itemDiv + 1;
                } else {
                    itemEmpty = itemEmpty + 1;
                }
                $(this).show();
            } else {
                $(this).hide();
            }
        });

        const minGridForInv = inv === "inventoryElement" ? Config.MainInventoryFixedSlotCount : SECOND_INVENTORY_GRID_SLOTS;
        if (itemDiv < minGridForInv) {
            if (itemEmpty > 0) {
                for (let i = 0; i < itemEmpty; i++) {
                    $(`#${inv} .item[data-group="0"]`).remove();
                }
            }
            const emptySlots = minGridForInv - itemDiv;
            for (let i = 0; i < emptySlots; i++) {
                $(`#${inv}`).append(`<div data-group="0" class="item"></div>`);
            }
        }

        INVENTORY.MAIN.SCROLL_GRID_TOP(inv);
    },

    SCROLL_GRID_TOP: function (elementId) {
        const el = document.getElementById(elementId);
        if (!el) return;
        el.scrollTop = 0;
    },

    CAPTURE_LAYOUT_FROM_DOM: function () {
        const slots = [];
        let slot = 0;
        $("#inventoryElement > .item").each(function () {
            const $row = $(this);
            const rowItem = $row.data("item");
            const domId = $row.attr("id") || "";
            if (domId === "item-money" || rowItem === "money") {
                slots.push({ k: "money", slot: slot++ });
                return;
            }
            if (domId === "item-gunbelt" || rowItem === "gunbelt") {
                slots.push({ k: "gunbelt", slot: slot++ });
                return;
            }
            if (domId === "item-gold" || rowItem === "gold") {
                slots.push({ k: "gold", slot: slot++ });
                return;
            }
            if (domId === "item-rol" || rowItem === "rol") {
                slots.push({ k: "rol", slot: slot++ });
                return;
            }
            if (rowItem && typeof rowItem === "object") {
                slots.push({
                    k: "item",
                    id: rowItem.id,
                    type: rowItem.type,
                    slot: slot++,
                });
                return;
            }
            slots.push({ k: "empty", slot: slot++ });
        });
        return { slots, slotCount: slots.length };
    },

    SORT_ITEMS_BY_LAYOUT: function (items) {
        const layout = mainInventoryLayoutCache;
        if (!layout || !Array.isArray(layout.slots) || layout.slots.length === 0) {
            return items.slice();
        }
        const data = {};
        let o = 0;
        for (let i = 0; i < layout.slots.length; i++) {
            const slot = layout.slots[i];
            if (slot && slot.k === "item") {
                const key = String(slot.type).replace(/[^a-zA-Z0-9_-]/g, "_") + "_" + String(slot.id);
                data[key] = o++;
            }
        }

        return items.slice().sort(function (a, b) {
            const ka = INVENTORY.MAIN.GET_ITEM_DOM_ID(a);
            const kb = INVENTORY.MAIN.GET_ITEM_DOM_ID(b);

            const oa = Object.prototype.hasOwnProperty.call(data, ka) ? data[ka] : 1e9;
            const ob = Object.prototype.hasOwnProperty.call(data, kb) ? data[kb] : 1e9;
            if (oa !== ob)
                return oa - ob;
            return String(ka).localeCompare(String(kb));
        });
    },

    SYNC_SUBGROUP_TO_CACHE: function (leavingTypes) {
        if (!Array.isArray(leavingTypes) || leavingTypes.length === 0) return;
        const layout = mainInventoryLayoutCache;
        if (!layout || !Array.isArray(layout.slots)) return;

        const typeSet = new Set(leavingTypes);
        const slots = layout.slots;

        for (let i = 0; i < slots.length; i++) {
            const s = slots[i];
            if (!s || s.k !== "item") continue;
            const key = String(s.type).replace(/[^a-zA-Z0-9_-]/g, "_") + "_" + String(s.id);
            const it = mainInventoryItemsCache[key];
            if (it && HOTBAR.IS_ITEM_ON_HOTBAR(it)) {
                slots[i] = { k: "empty", slot: i };
            }
        }

        function cachedSlotMatchesLeaving(s) {
            if (!s || s.k !== "item") return false;
            const key = String(s.type).replace(/[^a-zA-Z0-9_-]/g, "_") + "_" + String(s.id);
            const it = mainInventoryItemsCache[key];
            if (it) return typeSet.has(INVENTORY.MAIN.GET_ITEM_FILTER_GROUP(it));
            if (String(s.type) === "item_weapon") return typeSet.has(5);
            return false;
        }

        const movingIndices = [];
        for (let i = 0; i < slots.length; i++) {
            if (cachedSlotMatchesLeaving(slots[i])) {
                movingIndices.push(i);
            }
        }

        const domKeys = [];
        $("#inventoryElement > .item").each(function () {
            const $row = $(this);
            const rowItem = $row.data("item");
            const domId = $row.attr("id") || "";
            if (domId === "item-money" || rowItem === "money") return;
            if (domId === "item-gunbelt" || rowItem === "gunbelt") return;
            if (domId === "item-gold" || rowItem === "gold") return;
            if (domId === "item-rol" || rowItem === "rol") return;

            if (!rowItem || typeof rowItem !== "object") return;
            if (!typeSet.has(INVENTORY.MAIN.GET_ITEM_FILTER_GROUP(rowItem))) return;
            domKeys.push(INVENTORY.MAIN.GET_ITEM_DOM_ID(rowItem));
        });

        if (movingIndices.length === 0 || domKeys.length === 0) return;
        if (movingIndices.length !== domKeys.length) return;

        const keyToSlot = {};
        for (let i = 0; i < slots.length; i++) {
            const s = slots[i];
            if (!s || s.k !== "item") continue;
            const key = String(s.type).replace(/[^a-zA-Z0-9_-]/g, "_") + "_" + String(s.id);
            keyToSlot[key] = s;
        }

        for (let j = 0; j < movingIndices.length; j++) {
            const k = domKeys[j];
            const src = keyToSlot[k];
            if (!src) return;
            const destIdx = movingIndices[j];
            const copy = JSON.parse(JSON.stringify(src));
            copy.slot = destIdx;
            slots[destIdx] = copy;
        }
        for (let i = 0; i < slots.length; i++) {
            if (slots[i] && slots[i].k != null) {
                slots[i].slot = i;
            }
        }
        layout.slotCount = slots.length;
    },

    GET_ITEM_FILTER_GROUP: function (item) {
        if (!item || typeof item !== "object") return 0;
        if (item.type === "item_weapon") return 5;
        return Number(item.group) || 1;
    },

    RENDER_FILTERED_MAIN: function (filteredItems, filterTypes) {
        const $inv = $("#inventoryElement");
        $inv.html("");

        const visibleItems = INVENTORY.MAIN.SORT_ITEMS_BY_LAYOUT(filteredItems.filter(function (it) {
            return it && !HOTBAR.IS_ITEM_ON_HOTBAR(it);
        }));

        for (const it of visibleItems) {
            INVENTORY.MAIN.RENDER_ITEM_CELL(it);
        }

        INVENTORY.MAIN.APPEND_FIXED_HUD_SLOTS();

        const paddedTarget = Config.MainInventoryFixedSlotCount;
        while ($inv.children(".item").length < paddedTarget) {
            INVENTORY.MAIN.APPEND_EMPTY_SLOT();
        }
        INVENTORY.MAIN.TRIM_EMPTY_TAIL(paddedTarget);

        isOpen = true;
        INVENTORY.INIT_MOUSE_SOUND_HOVER();
        INVENTORY.MAIN.BIND_MAIN_WHEEL_SCALE();
        INVENTORY.MAIN.REFRESH_OVERFLOW();
    },

    APPLY_MAIN_GROUP_FILTER: function (key, types) {
        const goingToAll = key === 'all';
        const wasAll = activeMainGroupFilter === 'all';


        if (!goingToAll && wasAll) {
            mainInventoryLayoutCache = INVENTORY.MAIN.CAPTURE_LAYOUT_FROM_DOM();
        }

        const leavingSubgroupToAll = goingToAll && !wasAll && Array.isArray(activeMainGroupFilterTypes);
        const leavingTypesForMerge = leavingSubgroupToAll ? activeMainGroupFilterTypes.slice() : null;

        activeMainGroupFilter = goingToAll ? 'all' : key;
        activeMainGroupFilterTypes = goingToAll ? null : (Array.isArray(types) ? types.slice() : null);

        if (goingToAll && leavingTypesForMerge && leavingTypesForMerge.length > 0) {
            INVENTORY.MAIN.SYNC_SUBGROUP_TO_CACHE(leavingTypesForMerge);
        }


        let layoutForReplay = mainInventoryLayoutCache;
        if (goingToAll && wasAll) {
            layoutForReplay = INVENTORY.MAIN.CAPTURE_LAYOUT_FROM_DOM();
            mainInventoryLayoutCache = layoutForReplay;
        }

        const allItems = Object.values(mainInventoryItemsCache);

        INVENTORY.MAIN.INVENTORY_SETUP._skipCacheRefresh = true;
        try {
            if (goingToAll) {
                const layout = layoutForReplay;
                INVENTORY.MAIN.INVENTORY_SETUP(allItems, layout ? { slots: layout.slots, slotCount: layout.slotCount } : {});
            } else {
                const filterSet = activeMainGroupFilterTypes || [];
                const filtered = allItems.filter(function (it) {
                    return filterSet.includes(INVENTORY.MAIN.GET_ITEM_FILTER_GROUP(it));
                });
                INVENTORY.MAIN.RENDER_FILTERED_MAIN(filtered, filterSet);
            }
        } finally {
            INVENTORY.MAIN.INVENTORY_SETUP._skipCacheRefresh = false;
        }

        INVENTORY.MAIN.CLEAR_INV_SORT();
        INVENTORY.MAIN.INIT_INV_SORT();
        INVENTORY.MAIN.SCROLL_GRID_TOP("inventoryElement");

        if (goingToAll && (wasAll || (leavingTypesForMerge && leavingTypesForMerge.length))) {
            INVENTORY.MAIN.QUEUE_LAYOUT_SAVE();
        }
    },

    MOVE_INVENTORY_HUD: function (inv) {
        const inventoryHud = document.getElementById('inventoryHud');
        if (inv === 'main') {
            inventoryHud.style.left = '25%';
        } else if (inv === 'second') {
            inventoryHud.style.left = '1%';
        }
    },

    WEAPON_HAS_CLIP_AMMO: function (item) {
        if (!item || item.type !== "item_weapon" || !(item.used || item.used2))
            return false;
        if (!INVENTORY.WEAPON.SHOW_AMMO_UI(item))
            return false;

        if (!item.ammo || typeof item.ammo !== "object" || Array.isArray(item.ammo))
            return false;

        return Object.values(item.ammo).some((n) => Number(n) > 0);
    },

    ADD_MAIN_ITEM_ROW: function (domId, item) {

        const itemRowSelector = INVENTORY.MAIN.GET_ITEM_SELECTOR(domId);
        $(itemRowSelector).data("item", item);
        $(itemRowSelector).data("inventory", "main");

        $(itemRowSelector).dblclick(function () {
            if (INVENTORY.MAIN.IS_PAST_SLOT_CAP($(this))) return;
            if (type !== "main") return;

            if (item.used || item.used2) {
                $(this).find('.equipped-icon').hide();
                $.post(`https://${GetParentResourceName()}/UnequipWeapon`, JSON.stringify({
                    item: item.name,
                    id: item.id,
                }));

            } else {

                if (item.type == "item_weapon") {
                    $(this).find('.equipped-icon').show();
                }

                $.post(`https://${GetParentResourceName()}/UseItem`, JSON.stringify({
                    item: item.name,
                    type: item.type,
                    hash: item.hash,
                    amount: item.count,
                    id: item.id,
                }));
            }
        });

        $(itemRowSelector).contextMenu(function () {
            let item = $(this).data("item");

            const data = [];

            if (item.used || item.used2) {
                data.push({
                    text: LANGUAGE.unequip,
                    action: function () {
                        $(this).find('.equipped-icon').hide();
                        $.post(`https://${GetParentResourceName()}/UnequipWeapon`,
                            JSON.stringify({
                                item: item.name,
                                id: item.id,
                            })
                        );
                    },
                });
            } else {
                let lang;
                if (item.type != "item_weapon") {
                    lang = LANGUAGE.use;
                } else {
                    lang = LANGUAGE.equip;
                }
                data.push({
                    text: lang,
                    action: function () {
                        if (item.type == "item_weapon") {
                            $(this).find('.equipped-icon').show();
                        }
                        $.post(`https://${GetParentResourceName()}/UseItem`,
                            JSON.stringify({
                                item: item.name,
                                type: item.type,
                                hash: item.hash,
                                amount: item.count,
                                id: item.id,
                            })
                        );
                    },
                });
            }

            if (item.canRemove && type === "main") {
                const L = INVENTORY.MAIN.CTX_MENU_GIVE_DROP_LABELS();

                if (item.type === "item_weapon") {
                    data.push({
                        text: INVENTORY.MAIN.CTX_MENU_GIVE_ROOT(),
                        items: [[
                            {
                                text: L.giveQuick,
                                action: function () {
                                    return INVENTORY.MAIN.GIVE.WEAPON(item);
                                },
                            },
                        ]],
                    });
                    data.push({
                        text: INVENTORY.MAIN.CTX_MENU_DROP_ROOT(),
                        items: [[
                            {
                                text: L.dropQuick,
                                action: function () {
                                    return INVENTORY.MAIN.DROP.WEAPON(item);
                                },
                            },
                            {
                                text: L.dropAdvanced,
                                action: function () {
                                    return INVENTORY.MAIN.DROP.WEAPON_ADVANCED(item);
                                },
                            },
                        ]],
                    });
                } else if (item.type === "item_standard") {
                    if (item.count > 1) {
                        data.push({
                            text: INVENTORY.MAIN.CTX_MENU_GIVE_ROOT(),
                            items: [[
                                {
                                    text: L.giveAmount,
                                    action: function () {
                                        return INVENTORY.MAIN.GIVE.ITEM(item);
                                    },
                                },
                                {
                                    text: L.giveAll,
                                    action: function () {
                                        INVENTORY.MAIN.GIVE.ITEM_ALL(item);
                                    },
                                },
                            ]],
                        });
                        data.push({
                            text: INVENTORY.MAIN.CTX_MENU_DROP_ROOT(),
                            items: [[
                                {
                                    text: L.dropAmount,
                                    action: function () {
                                        return INVENTORY.MAIN.DROP.ITEM(item);
                                    },
                                },
                                {
                                    text: L.dropAll,
                                    action: function () {
                                        INVENTORY.MAIN.DROP.ITEM(item, true);
                                    },
                                },
                                {
                                    text: L.dropAdvanced,
                                    action: function () {
                                        INVENTORY.MAIN.DROP.ITEM_ADVANCED(item, false);
                                    },
                                },
                            ]],
                        });
                    } else {
                        data.push({
                            text: INVENTORY.MAIN.CTX_MENU_GIVE_ROOT(),
                            items: [[
                                {
                                    text: L.giveQuick,
                                    action: function () {
                                        INVENTORY.MAIN.GIVE.ITEM_ALL(item);
                                    },
                                },
                            ]],
                        });
                        data.push({
                            text: INVENTORY.MAIN.CTX_MENU_DROP_ROOT(),
                            items: [[
                                {
                                    text: L.dropQuick,
                                    action: function () {
                                        return INVENTORY.MAIN.DROP.ITEM(item);
                                    },
                                },
                                {
                                    text: L.dropAdvanced,
                                    action: function () {
                                        INVENTORY.MAIN.DROP.ITEM_ADVANCED(item, false);
                                    },
                                },
                            ]],
                        });
                    }
                }
            }

            if (item.type === "item_weapon") {

                const actionSubs = [];
                if ((item.used || item.used2) && item.canDegrade) {
                    actionSubs.push({
                        text: LANGUAGE.inspectweapon,
                        action: function () {
                            $.post(`https://${GetParentResourceName()}/inspection`, JSON.stringify({ id: item.id }));
                        },
                    });
                }

                if (INVENTORY.MAIN.WEAPON_HAS_CLIP_AMMO(item) && Config.ManualWeaponReload) {
                    actionSubs.push({
                        text: LANGUAGE.removebullets,
                        action: function () {
                            $.post(`https://${GetParentResourceName()}/removeBullets`, JSON.stringify({ id: item.id }));
                        },
                    });
                }

                if ((item.used || item.used2) && item.type === "item_weapon" && Config.AddAmmoItem && INVENTORY.WEAPON.SHOW_AMMO_UI(item) && Config.ManualWeaponReload) {
                    const ammoAllowed = item.ammoAllowed;
                    if (ammoAllowed && ammoAllowed.length) {
                        const itemRef = item;
                        const subs = ammoAllowed.map((ammoType) => {
                            const belt = Number(allplayerammo[ammoType]) || 0;
                            const hasOnWeapon = item.ammo && Object.prototype.hasOwnProperty.call(item.ammo, ammoType);
                            const onWeapon = hasOnWeapon ? Number(item.ammo[ammoType]) || 0 : null;
                            let countLabel = String(belt);
                            if (hasOnWeapon && belt > 0) {
                                countLabel = belt + " belt, " + onWeapon + " weapon";
                            } else if (hasOnWeapon) {
                                countLabel = onWeapon + " weapon";
                            }
                            return {
                                text: `${UTILS.GET_AMMO_TYPE_LABEL(ammoType)} (${countLabel})`,
                                action: function () {
                                    $.post(
                                        `https://${GetParentResourceName()}/setWeaponAmmoType`,
                                        JSON.stringify({
                                            id: itemRef.id,
                                            weaponName: itemRef.name,
                                            ammoType: ammoType,
                                        })
                                    );
                                },
                            };
                        });
                        actionSubs.push({
                            text: LANGUAGE.addweapontammotype,
                            items: [subs],
                        });
                    }
                }
                if ((item.used || item.used2) && INVENTORY.WEAPON.SHOW_AMMO_UI(item) && Config.ManualWeaponReload) {
                    actionSubs.push({
                        text: LANGUAGE.reloadweapon,
                        action: function () {
                            $.post(`https://${GetParentResourceName()}/reloadWeapon`, JSON.stringify({ id: item.id }));
                        },
                    });
                }
                if (item.canRemove && type === "main" && Config.EnableCopySerial && item.serial_number) {
                    actionSubs.push({
                        text: LANGUAGE.copyserial,
                        action: function () {
                            const clipElem = document.createElement('textarea');
                            clipElem.value = item.serial_number;
                            document.body.appendChild(clipElem);
                            clipElem.select();
                            document.execCommand('copy');
                            document.body.removeChild(clipElem);
                        },
                    });
                }
                if (actionSubs.length) {
                    data.push({
                        text: INVENTORY.MAIN.CTX_MENU_ACTIONS_ROOT(),
                        items: [actionSubs],
                    });
                }
            }

            if (item.metadata?.context) {
                item.metadata.context.forEach(option => {
                    data.push({
                        text: option.text,
                        action: function () {
                            option.itemid = item.id;
                            $.post(`https://${GetParentResourceName()}/ContextMenu`,
                                JSON.stringify(option)
                            );
                        }
                    });
                });
            }

            return [data];
        }, {
            offsetX: 1,
            offsetY: 1,
            beforeShow: function () {
                return type === "main";
            },
        });
    },

    HOTBAR_ALLOWS_TYPE: function (type) {
        const allow = String(Config.HotbarAllow).toLowerCase();
        if (allow === "weapons") return type === "item_weapon";
        if (allow === "items") return type === "item_standard";
        return type === "item_weapon" || type === "item_standard";
    },

    CAN_ASSIGN_TO_HOTBAR: function (item) {
        if (!item || typeof item !== "object") return false;
        if (UTILS.ITEM_DECAY_FULLY_SPOILED(item) || UTILS.ITEM_DURABILITY_FULLY_SPENT(item)) return false;
        if (!INVENTORY.MAIN.HOTBAR_ALLOWS_TYPE(item.type)) return false;

        if (item.type === "item_weapon")
            return true;

        if (item.type === "item_standard")
            return item.canUse;

        return false;
    },

    LOAD_ITEM_CELL: function (item, domId, group, count, limit, insertBefore) {

        if (item.type === "item_weapon") return;

        const { tooltipData, degradation, image, label, weight, durability } = UTILS.GET_ITEM_METADATA_INFO(item, false);
        const itemWeight = UTILS.GET_ITEM_WEIGHT(weight, count);
        const groupKey = UTILS.GET_GROUP_KEY(group);
        const { tooltipContent, url } = INVENTORY.TOOLTIP.GET_CONTENT(image, groupKey, group, limit, itemWeight, degradation, tooltipData, count, durability);
        const iconOpacityExtra = UTILS.ITEM_ICON_OPACITY_EXTRA(item);

        const html = `<div data-group='${group}' data-label='${label}' data-sortable="true" class='item item-filled' id='item-${domId}' data-tooltip='${tooltipContent}'>
        <span class='item-inv-icon' style='${UTILS.INVENTORY_SLOT_BACKGROUND_STYLE(url, "4.5vw", "7.7vh", iconOpacityExtra)}'></span>
        <div class='count'>
            <span style='color:Black'>${count}</span>
        </div>
    </div>`;
        if (insertBefore && insertBefore.length) {
            $(html).insertBefore(insertBefore);
        } else {
            $("#inventoryElement").append(html);
        }

        UTILS.APPLY_RARITY_SLOT_CLASSES($("#item-" + domId), item);
    },

    LOAD_WEAPON_CELL: function (item, domId, group, insertBefore) {
        if (item.type != "item_weapon") return;

        const weight = UTILS.GET_ITEM_WEIGHT(item.weight, 1);
        const serial = item.serial_number ? "<br>" + (LANGUAGE.labels?.serial ?? "Serial") + UTILS.ESCAPE_HTML(String(item.serial_number)) : "";
        const info = serial + INVENTORY.TOOLTIP.ADD_WEAPON(item);
        const url = imageCache[item.name];
        const label = item.custom_label ? item.custom_label : item.label;
        const html = `
    <div data-label='${label}' data-group='${group}' data-sortable="true" class='item item-filled' id='item-${domId}' data-tooltip="${weight + info}">
        <span class='item-inv-icon' style='${UTILS.INVENTORY_SLOT_BACKGROUND_STYLE(url, "4.5vw", "7.7vh", "")}'></span>
        ${INVENTORY.WEAPON.GET_AMMO_ICON(item)}
        <div class='equipped-icon' style='display: ${!item.used && !item.used2 ? "none" : "block"};'></div>
    </div> `;

        if (insertBefore && insertBefore.length) {
            $(html).insertBefore(insertBefore);
        } else {
            $("#inventoryElement").append(html);
        }
    },

    APPEND_MAIN_FIXED_CELL: function (label, description, item, data) {
        const $strip = $("#inventoryFixedSlotsStrip");
        const $parent = $strip.length ? $strip : $("#inventoryElement");
        $parent.append(`<div data-label='${label}' data-group='1' data-sortable="false" class='item item-filled item--fixed-strip' id='item-${item}'><span class='item-inv-icon' style='${UTILS.INVENTORY_SLOT_BACKGROUND_STYLE(`url(\"img/${item}.png\")`, "3.4vw", "5.05vh", "")}'></span></div>`);

        const opts = {
            offsetX: 1,
            offsetY: 1,
            beforeShow: function () {
                return type === "main";
            },
        };
        if (typeof data === "function") {
            $("#item-" + item).contextMenu(data, opts);
        } else {
            $("#item-" + item).contextMenu([data], opts);
        }
    },

    BUILD_GUNBELT_MENU_SUPPLIER: function () {
        return function () {
            return [INVENTORY.MAIN.BUILD_GUNBELT_CTX()];
        };
    },

    CTX_MENU_GIVE_ROOT: function () {
        const g = LANGUAGE && LANGUAGE.give;
        return g != null && String(g).length ? String(g) : "Give";
    },

    CTX_MENU_DROP_ROOT: function () {
        const d = LANGUAGE && LANGUAGE.drop;
        return d != null && String(d).length ? String(d) : "Drop";
    },

    CTX_MENU_ACTIONS_ROOT: function () {
        const a = LANGUAGE && LANGUAGE.contextmenuactions;
        return a != null && String(a).length ? String(a) : "Actions";
    },

    CTX_MENU_GIVE_DROP_LABELS: function () {
        return {
            giveAmount: (LANGUAGE && LANGUAGE.contextgiveamount) || "Give amount",
            giveAll: (LANGUAGE && LANGUAGE.contextgiveall) || "Give all",
            giveQuick: (LANGUAGE && LANGUAGE.contextgivequick) || "Quick give",
            dropAmount: (LANGUAGE && LANGUAGE.contextdropamount) || "Drop amount",
            dropAll: (LANGUAGE && LANGUAGE.contextdropall) || "Drop all",
            dropAdvanced: (LANGUAGE && LANGUAGE.contextdropadvanced) || "Drop advanced",
            dropQuick: (LANGUAGE && LANGUAGE.contextdropquick) || "Quick drop",
        };
    },

    /** One menu group: Give / Drop with hover flyouts (see contextMenu plugin `items`). */
    BUILD_MONEY_CTX: function () {
        const L = INVENTORY.MAIN.CTX_MENU_GIVE_DROP_LABELS();
        return [
            {
                text: INVENTORY.MAIN.CTX_MENU_GIVE_ROOT(),
                items: [[
                    { text: L.giveAmount, action: function () { INVENTORY.MAIN.GIVE.MONEY_AMOUNT(); } },
                    { text: L.giveAll, action: function () { INVENTORY.MAIN.GIVE.MONEY_ALL(); } },
                ]],
            },
            {
                text: INVENTORY.MAIN.CTX_MENU_DROP_ROOT(),
                items: [[
                    { text: L.dropAmount, action: function () { INVENTORY.MAIN.DROP.MONEY(false); } },
                    { text: L.dropAll, action: function () { INVENTORY.MAIN.DROP.MONEY(true); } },
                    { text: L.dropAdvanced, action: function () { INVENTORY.MAIN.DROP.MONEY_ADVANCED(false); } },
                ]],
            },
        ];
    },

    BUILD_GOLD_CTX: function () {
        const L = INVENTORY.MAIN.CTX_MENU_GIVE_DROP_LABELS();
        return [
            {
                text: INVENTORY.MAIN.CTX_MENU_GIVE_ROOT(),
                items: [[
                    { text: L.giveAmount, action: function () { INVENTORY.MAIN.GIVE.GOLD_AMOUNT(); } },
                    { text: L.giveAll, action: function () { INVENTORY.MAIN.GIVE.GOLD_ALL(); } },
                ]],
            },
            {
                text: INVENTORY.MAIN.CTX_MENU_DROP_ROOT(),
                items: [[
                    { text: L.dropAmount, action: function () { INVENTORY.MAIN.DROP.GOLD(false); } },
                    { text: L.dropAll, action: function () { INVENTORY.MAIN.DROP.GOLD(true); } },
                    { text: L.dropAdvanced, action: function () { INVENTORY.MAIN.DROP.GOLD_ADVANCED(false); } },
                ]],
            },
        ];
    },

    BUILD_ROLL_CTX: function () {
        const L = INVENTORY.MAIN.CTX_MENU_GIVE_DROP_LABELS();
        return [
            {
                text: INVENTORY.MAIN.CTX_MENU_DROP_ROOT(),
                items: [[
                    { text: L.dropAmount, action: function () { INVENTORY.MAIN.DROP.ROL(false); } },
                    { text: L.dropAll, action: function () { INVENTORY.MAIN.DROP.ROL(true); } },
                    { text: L.dropAdvanced, action: function () { INVENTORY.MAIN.DROP.ROL_ADVANCED(false); } },
                ]],
            },
        ];
    },

    BUILD_GUNBELT_CTX: function () {
        const subs = [];
        let ammoEmpty = true;
        if (allplayerammo) {
            for (const [ind, tab] of Object.entries(allplayerammo)) {
                if (tab > 0) {
                    ammoEmpty = false;
                    subs.push({
                        text: `${UTILS.GET_AMMO_TYPE_LABEL(ind)} : ${tab}`,
                        action: function () {
                            INVENTORY.MAIN.GIVE.AMMO(ind);
                        },
                    });
                }
            }
        }
        if (ammoEmpty) {
            const emptyLabel = (LANGUAGE.emptyammo != null ? LANGUAGE.emptyammo : LANGUAGE.empty) || "Empty";
            return [[{ text: emptyLabel, action: function () { } }]];
        }
        return [
            {
                text: INVENTORY.MAIN.CTX_MENU_GIVE_ROOT(),
                items: [subs],
            },
        ];
    },

    APPEND_FIXED_HUD_SLOTS: function () {
        INVENTORY.MAIN.APPEND_GUNBELT_GRID();
        INVENTORY.MAIN.APPEND_MONEY_GRID();
        INVENTORY.MAIN.APPEND_GOLD_GRID();
        INVENTORY.MAIN.APPEND_ROLL_GRID();
    },

    APPEND_DEFAULT_ORDER: function () {
        INVENTORY.MAIN.APPEND_FIXED_HUD_SLOTS();
    },

    APPEND_GUNBELT_GRID: function () {
        if (!Config.AddAmmoItem || $("#item-gunbelt").length) return;
        const gunbeltSupplier = INVENTORY.MAIN.BUILD_GUNBELT_MENU_SUPPLIER();
        INVENTORY.MAIN.APPEND_MAIN_FIXED_CELL(LANGUAGE.gunbeltlabel, LANGUAGE.gunbeltdescription, "gunbelt", gunbeltSupplier);
        $("#item-gunbelt").data("item", "gunbelt");
        $("#item-gunbelt").data("inventory", "none");
    },

    APPEND_MONEY_GRID: function () {
        if (!Config.AddDollarItem || $("#item-money").length) return;
        INVENTORY.MAIN.APPEND_MAIN_FIXED_CELL(LANGUAGE.inventorymoneylabel, LANGUAGE.inventorymoneydescription, "money", INVENTORY.MAIN.BUILD_MONEY_CTX());
        $("#item-money").data("item", "money");
        $("#item-money").data("inventory", "none");
    },

    APPEND_GOLD_GRID: function () {
        if (!Config.UseGoldItem || !Config.AddGoldItem || $("#item-gold").length) return;
        INVENTORY.MAIN.APPEND_MAIN_FIXED_CELL(LANGUAGE.inventorygoldlabel, LANGUAGE.inventorygolddescription, "gold", INVENTORY.MAIN.BUILD_GOLD_CTX());
        $("#item-gold").data("item", "gold");
        $("#item-gold").data("inventory", "none");
    },

    APPEND_ROLL_GRID: function () {
        if (!Config.UseRolItem || !Config.AddRollItem || $("#item-rol").length) return;
        const rl = LANGUAGE.inventoryrolllabel || "Roll";
        const rd = LANGUAGE.inventoryrolldescription || "";
        INVENTORY.MAIN.APPEND_MAIN_FIXED_CELL(rl, rd, "rol", INVENTORY.MAIN.BUILD_ROLL_CTX());
        $("#item-rol").data("item", "rol");
        $("#item-rol").data("inventory", "none");
    },

    RENDER_ITEM_CELL: function (item, insertBefore) {
        if (!item) return;
        const count = item.count;
        const limit = item.limit;
        const group = item.type != "item_weapon" ? !item.group ? 1 : item.group : 5;
        const domId = INVENTORY.MAIN.GET_ITEM_DOM_ID(item);
        INVENTORY.MAIN.LOAD_ITEM_CELL(item, domId, group, count, limit, insertBefore);
        INVENTORY.MAIN.LOAD_WEAPON_CELL(item, domId, group, insertBefore);
        if (insertBefore && insertBefore.length) {
            insertBefore.remove();
        }
        INVENTORY.MAIN.ADD_MAIN_ITEM_ROW(domId, item);
    },

    INVENTORY_SETUP: function (items, layout) {
        layout = layout || {};
        $("#inventoryElement").html("");
        INVENTORY.MAIN.EMPTY_FIXED_STRIP();
        const itemRows = [];
        if (items && items.length) {
            for (const [, item] of items.entries()) {
                if (item) itemRows.push(item);
            }
        }
        if (!INVENTORY.MAIN.INVENTORY_SETUP._skipCacheRefresh) {
            mainInventoryItemsCache = {};
            for (const it of itemRows) {
                const key = INVENTORY.MAIN.GET_ITEM_DOM_ID(it);
                mainInventoryItemsCache[key] = it;
            }
            if (layout.slots && Array.isArray(layout.slots) && layout.slots.length > 0) {
                mainInventoryLayoutCache = {
                    slots: JSON.parse(JSON.stringify(layout.slots)),
                    slotCount: layout.slotCount || layout.slots.length,
                };
            }
        }

        const slotsFromSave = layout.slots;
        if (slotsFromSave && Array.isArray(slotsFromSave) && slotsFromSave.length > 0) {
            const $inv = $("#inventoryElement");
            const paddedTargetPre = Config.MainInventoryFixedSlotCount;
            const slotsReplay = UTILS.TRIM_TRAILING_EMPTY_SLOTS(slotsFromSave.slice(), paddedTargetPre);

            const itemMap = {};
            for (const it of itemRows) {
                itemMap[INVENTORY.MAIN.GET_ITEM_DOM_ID(it)] = it;
            }

            const usedKeys = {};
            for (let i = 0; i < slotsReplay.length; i++) {
                const slot = slotsReplay[i];
                if (!slot || typeof slot !== "object") continue;
                if (slot && slot.k === "item") {
                    const key = String(slot.type).replace(/[^a-zA-Z0-9_-]/g, "_") + "_" + String(slot.id);
                    const it = itemMap[key];
                    if (it && !usedKeys[key]) {
                        if (HOTBAR.IS_ITEM_ON_HOTBAR(it)) {
                            INVENTORY.MAIN.APPEND_EMPTY_SLOT();
                        } else {
                            INVENTORY.MAIN.RENDER_ITEM_CELL(it);
                        }
                        usedKeys[key] = true;
                    } else {
                        INVENTORY.MAIN.APPEND_EMPTY_SLOT();
                    }
                } else if (slot.k === "empty") {
                    INVENTORY.MAIN.APPEND_EMPTY_SLOT();
                } else if (slot.k === "gunbelt") {
                    INVENTORY.MAIN.APPEND_EMPTY_SLOT();
                } else if (slot.k === "money") {
                    INVENTORY.MAIN.APPEND_EMPTY_SLOT();
                } else if (slot.k === "gold") {
                    INVENTORY.MAIN.APPEND_EMPTY_SLOT();
                } else if (slot.k === "rol") {
                    INVENTORY.MAIN.APPEND_EMPTY_SLOT();
                } else {
                    INVENTORY.MAIN.APPEND_EMPTY_SLOT();
                }
            }
            for (const it of itemRows) {
                const key = INVENTORY.MAIN.GET_ITEM_DOM_ID(it);
                if (!usedKeys[key]) {
                    if (HOTBAR.IS_ITEM_ON_HOTBAR(it)) {
                        INVENTORY.MAIN.APPEND_EMPTY_SLOT();
                        usedKeys[key] = true;
                        continue;
                    }
                    const $empty = $inv.children(".item").filter(function () {
                        return INVENTORY.MAIN.IS_MAIN_EMPTY_SLOT($(this));
                    }).first();
                    if ($empty.length) {
                        INVENTORY.MAIN.RENDER_ITEM_CELL(it, $empty);
                    } else {
                        INVENTORY.MAIN.RENDER_ITEM_CELL(it);
                    }
                    usedKeys[key] = true;
                }
            }

            const paddedTarget = paddedTargetPre;
            while ($("#inventoryElement > .item").length < paddedTarget) {
                INVENTORY.MAIN.APPEND_EMPTY_SLOT();
            }
            INVENTORY.MAIN.TRIM_EMPTY_TAIL(paddedTarget);

        } else {
            for (const it of itemRows) {
                if (HOTBAR.IS_ITEM_ON_HOTBAR(it)) {
                    INVENTORY.MAIN.APPEND_EMPTY_SLOT();
                } else {
                    INVENTORY.MAIN.RENDER_ITEM_CELL(it);
                }
            }
            const paddedTargetFallback = Config.MainInventoryFixedSlotCount;
            while ($("#inventoryElement > .item").length < paddedTargetFallback) {
                INVENTORY.MAIN.APPEND_EMPTY_SLOT();
            }
            INVENTORY.MAIN.TRIM_EMPTY_TAIL(paddedTargetFallback);
        }

        INVENTORY.MAIN.REPLACE_LEGACY_FIXED_CELLS();
        INVENTORY.MAIN.APPEND_FIXED_HUD_SLOTS();

        isOpen = true;
        INVENTORY.INIT_MOUSE_SOUND_HOVER();
        INVENTORY.MAIN.BIND_MAIN_WHEEL_SCALE();
        INVENTORY.MAIN.REFRESH_OVERFLOW();
    },

    CANCEL_DRAG_ACTIVE: function () {
        try {
            if (typeof $ !== "undefined" && $.ui && $.ui.ddmanager && $.ui.ddmanager.current) {
                const inst = $.ui.ddmanager.current;
                if (inst && typeof inst.cancel === "function") {
                    inst.cancel();
                }
            }
        } catch (e) {
            /* ignore */
        }
        try {
            $("body").children(".ui-draggable-dragging").remove();
        } catch (e2) {
            /* ignore */
        }
    },

    SYNC_DROP_ZONE_LABEL: function () {
        const el = document.getElementById("mainInventoryDropZoneLabel");
        if (!el) return;
        el.textContent = LANGUAGE.invdropzonehint;
    },

    PERFORM_DROP_ON_TARGET: function ($drag, event) {
        const item = $drag.data("item");
        if (!item.canRemove || type !== "main") return;

        const ev = event && event.originalEvent ? event.originalEvent : event;
        const shift = !!(event && event.shiftKey) || !!(ev && ev.shiftKey);
        const alt = !!(event && event.altKey) || !!(ev && ev.altKey);

        if (item.type === "item_weapon") {
            INVENTORY.MAIN.DROP.WEAPON(item);
            return;
        }


        const c = parseInt(String(item.count), 10) || 0;
        if (c <= 1) {
            INVENTORY.MAIN.DROP.ITEM(item);
            return;
        }
        if (shift) {
            INVENTORY.MAIN.DROP.ITEM(item, true);
            return;
        }
        if (alt) {
            const half = Math.ceil(c / 2);
            INVENTORY.MAIN.DROP.ITEM(item, false, half);
            return;
        }
        INVENTORY.MAIN.DROP.ITEM(item);
    },

    TEARDOWN_MAIN_DROP_DND: function () {
        const $z = $("#mainInventoryDropZone");
        if ($z.length && $z.data("ui-droppable")) {
            try {
                $z.droppable("destroy");
            } catch (e) {
                /* ignore */
            }
        }
    },

    INIT_MAIN_DROP_DND: function () {
        INVENTORY.MAIN.TEARDOWN_MAIN_DROP_DND();
        if (type !== "main") return;
        const $z = $("#mainInventoryDropZone");
        if (!$z.length) return;
        INVENTORY.MAIN.SYNC_DROP_ZONE_LABEL();
        $z.droppable({
            tolerance: "pointer",
            accept: function ($dr) {
                const $d = $($dr);
                if (!$d.closest("#inventoryElement").length || !$d.hasClass("item")) return false;
                const it = $d.data("item");

                if (!it.canRemove) return false;
                if (INVENTORY.MAIN.IS_PAST_SLOT_CAP($d)) return false;
                return it.type === "item_standard" || it.type === "item_weapon";
            },
            drop: function (event, ui) {
                const $drag = ui.draggable;
                INVENTORY.MAIN.PERFORM_DROP_ON_TARGET($drag, event);
                $drag.data("invDropAccepted", true);
            },
        });
    },

    CLEAR_INV_SORT: function () {
        INVENTORY.MAIN.CANCEL_DRAG_ACTIVE();
        INVENTORY.MAIN.TEARDOWN_MAIN_DROP_DND();
        clearTimeout(invSortTimer);
        const $inv = $("#inventoryElement");
        $inv.children(".item").each(function () {
            const $el = $(this);
            if ($el.data("ui-draggable")) {
                try {
                    $el.draggable("destroy");
                } catch (e) {
                    //ignore 
                }
            }
            if ($el.data("ui-droppable")) {
                try {
                    $el.droppable("destroy");
                } catch (e) {
                    //ignore 
                }
            }
        });
        if ($inv.hasClass("ui-sortable")) {
            try {
                $inv.sortable("destroy");
            } catch (sortableDestroyError) {
                //ignore 
            }
        }
        $inv.children(".item").each(function () {
            $(this).removeAttr("data-hotbar-inv-drag").removeAttr("data-hotbar-empty-drop");
        });

        HOTBAR.DND.TEARDOWN_HUD();

    },

    SWAP_MAIN_SLOTS: function ($a, $b) {
        if (!$a.length || !$b.length || $a[0] === $b[0]) return;
        const $marker = $("<div/>").attr("data-inv-swap-tmp", "1");
        $a.before($marker);
        $b.before($a);
        $marker.before($b);
        $marker.remove();
    },

    QUEUE_LAYOUT_SAVE: function () {

        if (activeMainGroupFilter !== 'all') return;
        clearTimeout(invSortTimer);
        invSortTimer = setTimeout(function () {
            const slots = [];
            let slot = 0;
            $("#inventoryElement > .item").each(function () {
                const $row = $(this);
                const rowItem = $row.data("item");
                const domId = $row.attr("id") || "";
                if (domId === "item-money" || rowItem === "money") {
                    slots.push({ k: "money", slot: slot++ });
                    return;
                }
                if (domId === "item-gunbelt" || rowItem === "gunbelt") {
                    slots.push({ k: "gunbelt", slot: slot++ });
                    return;
                }
                if (domId === "item-gold" || rowItem === "gold") {
                    slots.push({ k: "gold", slot: slot++ });
                    return;
                }
                if (domId === "item-rol" || rowItem === "rol") {
                    slots.push({ k: "rol", slot: slot++ });
                    return;
                }
                if (rowItem && typeof rowItem === "object") {
                    const itemName = rowItem.name != null ? rowItem.name : rowItem.item;
                    slots.push({
                        k: "item",
                        id: rowItem.id,
                        type: rowItem.type,
                        item: itemName,
                        count: rowItem.count != null ? rowItem.count : 0,
                        slot: slot++
                    });
                    return;
                }
                slots.push({ k: "empty", slot: slot++ });
            });
            const maxSlots = Config.MainInventoryFixedSlotCount;
            UTILS.TRIM_TRAILING_EMPTY_SLOTS(slots, maxSlots);
            for (let i = 0; i < slots.length; i++) {
                slots[i].slot = i;
            }
            const slotCount = slots.length;
            $.post(`https://${GetParentResourceName()}/SaveInventoryLayout`, JSON.stringify({ slots: slots, slotCount: slotCount }));
        }, 150);
    },

    INIT_INV_SORT: function () {
        const $inv = $("#inventoryElement");
        const $slots = $inv.children(".item");

        INVENTORY.MAIN.REFRESH_OVERFLOW();

        $slots.each(function () {
            const $slot = $(this);
            $slot.droppable({
                accept: function ($draggable) {
                    const $drop = $(this);
                    if ($draggable.hasClass("hotbar-slot-icon")) {
                        if (INVENTORY.MAIN.IS_PAST_SLOT_CAP($drop)) return false;
                        const p = $draggable.data("invHotbarPointer");
                        if (!p) return false;
                        if (INVENTORY.MAIN.IS_POINT_OVER_HOTBAR(p.x, p.y)) return false;
                        return INVENTORY.MAIN.IS_POINT_IN_MAIN_GRID(p.x, p.y);
                    }

                    if ($draggable.hasClass("weapon-attachment-chip")) {
                        if (!WEAPON_ATTACHMENTS || !WEAPON_ATTACHMENTS.IS_OPEN()) return false;
                        const p = $draggable.data("invAttachmentPointer");
                        if (!p) return false;
                        if (INVENTORY.MAIN.IS_POINT_OVER_HOTBAR(p.x, p.y)) return false;
                        return INVENTORY.MAIN.IS_POINT_IN_MAIN_GRID(p.x, p.y);
                    }

                    if ($draggable.closest("#inventoryElement").length > 0 && $draggable.hasClass("item")) {
                        const $drag = $draggable;
                        const dragOver = INVENTORY.MAIN.IS_PAST_SLOT_CAP($drag);
                        const dropOver = INVENTORY.MAIN.IS_PAST_SLOT_CAP($drop);
                        if (!dragOver && !dropOver) return true;
                        if (!dragOver && dropOver) return false;
                        return true;
                    }

                    if ($draggable.closest("#secondInventoryElement").length > 0 && $draggable.hasClass("item")) {
                        return INVENTORY.MAIN.IS_MAIN_EMPTY_SLOT($drop) && !INVENTORY.MAIN.IS_PAST_SLOT_CAP($drop);
                    }
                    return false;
                },
                tolerance: "pointer",
                greedy: true,
                drop: function (event, ui) {
                    const $drag = ui.draggable;
                    const $drop = $(this);

                    if ($drag.hasClass("hotbar-slot-icon")) {
                        if (INVENTORY.MAIN.IS_PAST_SLOT_CAP($drop)) return;
                        const hx = event.clientX ?? event.originalEvent?.clientX;
                        const hy = event.clientY ?? event.originalEvent?.clientY;
                        if (hx != null && hy != null && INVENTORY.MAIN.IS_POINT_OVER_HOTBAR(hx, hy)) {
                            return;
                        }
                        if (hx == null || hy == null || !INVENTORY.MAIN.IS_POINT_IN_MAIN_GRID(hx, hy)) {
                            return;
                        }
                        const idx = parseInt($drag.closest(".hotbar-slot").attr("data-hotbar-index"), 10);
                        if (Number.isNaN(idx)) return;
                        if (INVENTORY.MAIN.IS_MAIN_EMPTY_SLOT($drop)) {
                            HOTBAR.RELEASE_TO_MAIN_EMPTY_CELL(idx, $drop);
                        } else {
                            const mainItem = $drop.data("item");
                            if (!INVENTORY.MAIN.CAN_ASSIGN_TO_HOTBAR(mainItem)) return;
                            HOTBAR.ASSIGN_SLOT(idx, mainItem, $drop);
                        }
                        return;
                    }

                    if ($drag.hasClass("weapon-attachment-chip")) {
                        const cx = event.clientX ?? event.originalEvent?.clientX;
                        const cy = event.clientY ?? event.originalEvent?.clientY;
                        if (cx != null && cy != null && INVENTORY.MAIN.IS_POINT_OVER_HOTBAR(cx, cy)) {
                            return;
                        }
                        if (cx == null || cy == null || !INVENTORY.MAIN.IS_POINT_IN_MAIN_GRID(cx, cy)) {
                            return;
                        }
                        const attachmentItemName = $drag.data("itemName");
                        if (attachmentItemName != null && WEAPON_ATTACHMENTS && WEAPON_ATTACHMENTS.CHIP_RETURN_TO_MAIN) {
                            WEAPON_ATTACHMENTS.CHIP_RETURN_TO_MAIN(
                                attachmentItemName,
                                $drag.data("slotCategory"),
                                $drag.data("slotIndex")
                            );
                        }
                        return;
                    }


                    if ($drag.closest("#inventoryElement").length > 0) {
                        const x = event.clientX ?? event.originalEvent?.clientX;
                        const y = event.clientY ?? event.originalEvent?.clientY;

                        if (x != null && y != null && INVENTORY.MAIN.IS_POINT_OVER_HOTBAR(x, y)) {
                            return;
                        }
                        if (x == null || y == null || !INVENTORY.MAIN.IS_POINT_IN_MAIN_GRID(x, y)) {
                            return;
                        }

                        if (!$drag.length || $drag[0] === $drop[0]) return;
                        $drag.data("invDropAccepted", true);
                        INVENTORY.MAIN.SWAP_MAIN_SLOTS($drag, $drop);
                        INVENTORY.MAIN.QUEUE_LAYOUT_SAVE();
                        return;
                    }


                    if ($drag.closest("#secondInventoryElement").length > 0 && INVENTORY.MAIN.IS_MAIN_EMPTY_SLOT($drop)) {
                        const sx = event.clientX ?? event.originalEvent?.clientX;
                        const sy = event.clientY ?? event.originalEvent?.clientY;
                        if (sx == null || sy == null || !INVENTORY.MAIN.IS_POINT_IN_MAIN_GRID(sx, sy)) {
                            return;
                        }
                        const dragItemData = $drag.data("item");
                        if (!dragItemData) return;
                        $drag.data("invDropAccepted", true);
                        const info = $("#secondInventoryElement").data("info");
                        pendingDropTargetSlot = $drop[0];

                        if (type in INVENTORY.SECONDARY.ACTION_TAKE_LIST) {
                            const { action, id, customtype } = INVENTORY.SECONDARY.ACTION_TAKE_LIST[type];
                            INVENTORY.SECONDARY.POST_ACTION(action, dragItemData, id(), customtype, info);
                        } else if (type === "store") {
                            INVENTORY.DISABLE(500);

                            if (dragItemData.type != "item_weapon") {
                                if (dragItemData.count === 1 || isShiftActive === true) {
                                    const qty = isShiftActive ? dragItemData.count : 1;
                                    INVENTORY.SECONDARY.TAKE_FROM_STORE(dragItemData, qty);
                                    return;
                                }

                                dialog.prompt({
                                    title: LANGUAGE.prompttitle,
                                    button: LANGUAGE.promptaccept,
                                    required: true,
                                    item: dragItemData,
                                    type: dragItemData.type,
                                    input: {
                                        type: "number",
                                        autofocus: "true",
                                    },
                                    validate: function (value) {
                                        if (!value) {
                                            dialog.close();
                                            return;
                                        }

                                        if (!UTILS.IS_INT(value)) {
                                            return;
                                        }

                                        INVENTORY.SECONDARY.TAKE_FROM_STORE(dragItemData, value);
                                    },
                                });
                            } else {
                                INVENTORY.SECONDARY.TAKE_FROM_STORE(dragItemData, 1);
                            }
                        }
                    }
                },
            });
            if (!INVENTORY.MAIN.IS_MAIN_EMPTY_SLOT($slot)) {
                $slot.draggable({
                    helper: function (event) {
                        return UTILS.BUILD_INVENTORY_DRAG_HELPER(this, event);
                    },
                    appendTo: "body",
                    zIndex: 99999,
                    revert: function () {
                        return !$(this).data("invDropAccepted");
                    },
                    scroll: false,
                    distance: 8,
                    containment: "document",
                    drag: INVENTORY.MAIN.MAIN_INV_AUTO_SCROLL_DRAG,
                    start: function (event) {
                        if (disabled) return false;
                        if (INVENTORY.MAIN.IS_PAST_SLOT_CAP($(this))) return false;
                        const $row = $(this);
                        altDragActive = !!(event.altKey || event.originalEvent?.altKey);
                        stopTooltip = true;
                        itemData = $row.data("item");
                        itemInventory = $row.data("inventory");
                        $(".tooltip").remove();
                        $row.data("invDropAccepted", false);
                        $row.css("opacity", "");
                        $row.children(".item-inv-icon").first().css("opacity", 0.35);
                    },
                    stop: function () {
                        const $row = $(this);
                        altDragActive = false;
                        stopTooltip = false;
                        itemData = $row.data("item");
                        itemInventory = $row.data("inventory");
                        $row.removeData("invDropAccepted");
                        $row.css("opacity", "");
                        $row.children(".item-inv-icon").first().css("opacity", UTILS.ITEM_SLOT_OPACITY($row.data("item")));
                    },
                });
            }
        });

        HOTBAR.INIT_MAIN_DND();

        INVENTORY.MAIN.INIT_MAIN_DROP_DND();

    },

    MAIN_UPDATE_ITEM: function (item) {
        if (!item || item.id == null || !item.type) return;

        const cacheKey = INVENTORY.MAIN.GET_ITEM_DOM_ID(item);
        mainInventoryItemsCache[cacheKey] = item;

        if (Config.EnableHandCraftButton && $("#handCraftingPanel").is(":visible")) {
            CRAFTING.REFRESH_REQUIREMENTS();
        }

        if (item.type === "item_weapon") {
            $("#secondInventoryElement .item").each(function () {
                const d = $(this).data("item");
                if (!d || d.type !== "item_weapon" || Number(d.id) !== Number(item.id)) return;
                const merged = Object.assign({}, d, item);
                if (!("current_ammo_type" in item)) {
                    delete merged.current_ammo_type;
                }
                $(this).data("item", merged);
                $(this).find(".weapon-ammo-count").remove();
                $(this).children(".count").remove();
                $(this).append(INVENTORY.WEAPON.GET_AMMO_ICON(merged));
            });
            if (typeof hotbarSlotData !== "undefined" && Array.isArray(hotbarSlotData)) {
                let hbChanged = false;
                for (let i = 0; i < hotbarSlotData.length; i++) {
                    const e = hotbarSlotData[i];
                    if (e && e.type === "item_weapon" && Number(e.id) === Number(item.id)) {
                        e.ammo = item.ammo;
                        e.defaultClipSize = item.defaultClipSize;
                        if ("current_ammo_type" in item) {
                            e.current_ammo_type = item.current_ammo_type;
                        } else {
                            delete e.current_ammo_type;
                        }

                        hbChanged = true;
                    }
                }
                if (hbChanged) {
                    HOTBAR.REFRESH_SLOT_VISUALS();
                }
            }
        } else if (typeof hotbarSlotData !== "undefined" && Array.isArray(hotbarSlotData)) {
            let hbChanged = false;
            for (let i = 0; i < hotbarSlotData.length; i++) {
                const e = hotbarSlotData[i];
                if (e && e.type === "item_standard" && Number(e.id) === Number(item.id)) {
                    e.count = item.count;
                    e.metadata = item.metadata;
                    e.percentage = item.percentage;
                    e.durability = item.durability;
                    hbChanged = true;
                }
            }
            if (hbChanged) {
                HOTBAR.REFRESH_SLOT_VISUALS();
            }
        }

        if (activeMainGroupFilter !== 'all') {
            const filterSet = activeMainGroupFilterTypes || [];
            if (!filterSet.includes(INVENTORY.MAIN.GET_ITEM_FILTER_GROUP(item))) return;
        }

        const domId = INVENTORY.MAIN.GET_ITEM_DOM_ID(item);
        const selector = INVENTORY.MAIN.GET_ITEM_SELECTOR(domId);
        const $existing = $(selector);

        if ($existing.length) {

            $existing.addClass("item-filled");
            if (item.type === "item_weapon") {
                let $icon = $existing.children(".item-inv-icon");
                if (!$icon.length) {
                    $icon = $("<span/>").addClass("item-inv-icon").prependTo($existing);
                }
                const u = imageCache[item.name];
                $existing.css("opacity", "");
                $icon.attr("style", UTILS.INVENTORY_SLOT_BACKGROUND_STYLE(u, "4.5vw", "7.7vh", UTILS.ITEM_ICON_OPACITY_EXTRA(item)));
                $existing.find(".weapon-ammo-count").remove();
                $existing.children(".count").remove();
                $existing.append(INVENTORY.WEAPON.GET_AMMO_ICON(item));
            } else {
                let $icon = $existing.children(".item-inv-icon");
                if (!$icon.length) {
                    $icon = $("<span/>").addClass("item-inv-icon").prependTo($existing);
                }
                const { tooltipData, degradation, image, weight, durability } = UTILS.GET_ITEM_METADATA_INFO(item, false);
                const itemWeight = UTILS.GET_ITEM_WEIGHT(weight, item.count);
                const group = item.type != "item_weapon" ? (!item.group ? 1 : item.group) : 5;
                const groupKey = UTILS.GET_GROUP_KEY(group);
                const { url } = INVENTORY.TOOLTIP.GET_CONTENT(image, groupKey, group, item.limit, itemWeight, degradation, tooltipData, item.count, durability);
                $existing.css("opacity", "");
                $icon.attr("style", UTILS.INVENTORY_SLOT_BACKGROUND_STYLE(url, "4.5vw", "7.7vh", UTILS.ITEM_ICON_OPACITY_EXTRA(item)));
                $existing.find(".count span").text(item.count);
            }
            if (item.type === "item_weapon") {
                const prev = $existing.data("item");
                if (prev && typeof prev === "object" && (item.used || item.used2) && item.weaponLiveStatus == null && prev.weaponLiveStatus) {
                    item = Object.assign({}, item, { weaponLiveStatus: prev.weaponLiveStatus });
                }
            }
            $existing.data("item", item);
            UTILS.APPLY_RARITY_SLOT_CLASSES($existing, item);
            INVENTORY.MAIN.REFRESH_OVERFLOW();
        } else {

            const $inv = $("#inventoryElement");

            let $empty = null;
            if (pendingDropTargetSlot) {
                const $pending = $(pendingDropTargetSlot);
                if ($pending.length && INVENTORY.MAIN.IS_MAIN_EMPTY_SLOT($pending)) {
                    $empty = $pending;
                }
                pendingDropTargetSlot = null;
            }
            if (!$empty || !$empty.length) {
                $empty = $inv.children(".item").filter(function () {
                    return INVENTORY.MAIN.IS_MAIN_EMPTY_SLOT($(this));
                }).first();
            }

            let $newSlot;
            if ($empty && $empty.length) {
                INVENTORY.MAIN.RENDER_ITEM_CELL(item, $empty);
                $newSlot = $empty;
            } else {
                INVENTORY.MAIN.APPEND_EMPTY_SLOT();
                $newSlot = $inv.children(".item").last();
                INVENTORY.MAIN.RENDER_ITEM_CELL(item, $newSlot);
            }

            INVENTORY.MAIN.CLEAR_INV_SORT();
            INVENTORY.MAIN.INIT_INV_SORT();
            INVENTORY.MAIN.QUEUE_LAYOUT_SAVE();
        }
    },

    WEAPON_USED_UPDATE: function (id, used, used2, weaponLiveStatus) {
        if (id == null) return;
        used = !!used;
        used2 = !!used2;

        const applyToSlot = ($row) => {
            $row.find(".equipped-icon").css("display", used || used2 ? "block" : "none");
            const rowData = $row.data("item");
            if (rowData && typeof rowData === "object") {
                rowData.used = used;
                rowData.used2 = used2;
                if (used || used2) {
                    if (weaponLiveStatus) {
                        rowData.weaponLiveStatus = weaponLiveStatus;
                    }
                } else {
                    delete rowData.weaponLiveStatus;
                }
                $row.data("item", rowData);
            }
        };


        const domId = "item_weapon_" + String(id);
        const selector = INVENTORY.MAIN.GET_ITEM_SELECTOR(domId);
        const $row = $(selector);
        if ($row.length) {
            applyToSlot($row);
        }


        $("#secondInventoryElement .item").each(function () {
            const d = $(this).data("item");
            if (!d || d.type !== "item_weapon" || Number(d.id) !== Number(id)) return;
            applyToSlot($(this));
        });

        if (typeof hotbarSlotData !== "undefined" && Array.isArray(hotbarSlotData)) {
            let changed = false;
            for (let i = 0; i < hotbarSlotData.length; i++) {
                const entry = hotbarSlotData[i];
                if (entry && entry.type === "item_weapon" && Number(entry.id) === Number(id)) {
                    entry.used = used;
                    entry.used2 = used2;
                    changed = true;
                }
            }
            if (changed) {
                HOTBAR.REFRESH_SLOT_VISUALS();
            }
        }
    },

    MAIN_REMOVE_ITEM: function (id, itemType) {
        const domId = String(itemType) + "_" + String(id);

        delete mainInventoryItemsCache[domId];

        if (Config.EnableHandCraftButton && $("#handCraftingPanel").is(":visible")) {
            CRAFTING.REFRESH_REQUIREMENTS();
        }

        const $slot = $(INVENTORY.MAIN.GET_ITEM_SELECTOR(domId));
        if (!$slot.length) return;

        $slot.replaceWith('<div class="item" data-group="0" data-sortable="true"></div>');

        INVENTORY.MAIN.TRIM_EMPTY_TAIL(Config.MainInventoryFixedSlotCount);

        INVENTORY.MAIN.CLEAR_INV_SORT();
        INVENTORY.MAIN.INIT_INV_SORT();
    },

    // change the speed of the wheel for smother changes
    BIND_MAIN_WHEEL_SCALE: function () {
        const el = document.getElementById("inventoryElement");
        if (!el || el.dataset.mainInvWheelBound === "1") return;
        el.dataset.mainInvWheelBound = "1";
        const raw = Number(Config.MainInventoryWheelScale) || 0.45;
        el.addEventListener(
            "wheel",
            function (e) {
                if (el.scrollHeight <= el.clientHeight) return;
                e.preventDefault();
                el.scrollTop += e.deltaY * raw;
            },
            { passive: false }
        );
    },

    INIT_CROSS_INV_DRAG: function ($items) {
        $items.draggable({
            helper: function (event) {
                return UTILS.BUILD_INVENTORY_DRAG_HELPER(this, event);
            },
            appendTo: 'body',
            zIndex: 99999,
            revert: 'invalid',
            distance: 8,
            start: function (event) {
                if (disabled) { return false; }
                altDragActive = !!(event.altKey || event.originalEvent?.altKey);
                stopTooltip = true;
                itemData = $(this).data("item");
                itemInventory = $(this).data("inventory");
                if (itemInventory === "main") {
                    $("#inventoryHud").fadeOut();
                }
            },
            stop: function () {
                altDragActive = false;
                stopTooltip = false;
                itemData = $(this).data("item");
                itemInventory = $(this).data("inventory");
                if (itemInventory === "main") {
                    $("#inventoryHud").fadeIn(100, function () {

                        INVENTORY.MAIN.SCHEDULE_MAIN_GROUP_STRIP();
                        if ($("#secondInventoryHud").is(":visible")) {
                            INVENTORY.SECONDARY.SCHEDULE_GROUP_STRIP();
                        }

                    });
                }
            }
        });
    },
};

$("document").ready(function () {

    INVENTORY.MAIN.INIT_STATIC_CAROUSEL();

    $("#secondInventoryHud").draggable();
    $("#inventoryHud").draggable();

    $("#inventoryHud").hide();
    $("#secondInventoryHud").hide();
    $('#disabler').hide();

    $("body").on("keyup", function (key) {
        if (Config.closeKeys.includes(key.which)) {
            INVENTORY.CLOSE();
            document.querySelectorAll('.dropdownButton[data-type="itemtype"], .dropdownButton1[data-type="itemtype"]').forEach(btn => btn.classList.remove('active'));
            document.querySelector(`.dropdownButton[data-param="all"][data-type="itemtype"], .dropdownButton1[data-param="all"][data-type="itemtype"]`)?.classList.add('active');
        }
    });

    document.onkeydown = function (e) {
        isShiftActive = e.shiftKey;
    };

    document.onkeyup = function (e) {
        isShiftActive = e.shiftKey;
    };

    INVENTORY.SECONDARY.INIT_HANDLERS();

    $(document).on("click", "#close", function () {
        INVENTORY.CLOSE();
    });

    $(document).on("click", "#inventorySortBtn", function () {
        if (type !== "main") return;
        $("#sortConfirmPopup").toggle();
    });

    $(document).on("click", "#sortConfirmYes", function () {
        $("#sortConfirmPopup").hide();
        INVENTORY.MAIN.AUTO_SORT();
    });

    $(document).on("click", "#sortConfirmNo", function () {
        $("#sortConfirmPopup").hide();
    });

    $("#inventorySaddleBtn").on("click", function (ev) {
        if (ev) {
            ev.preventDefault();
            ev.stopPropagation();
        }
        if (!Config.EnableSaddleButton) return;

        if ($("#inventorySaddleBtn").prop("disabled")) return;

        $.post(`https://${GetParentResourceName()}/inventorySaddle`, JSON.stringify({}));
    });

    document.addEventListener("contextmenu", function (e) {
        const t = e.target;
        if (!t) return;

        if (t.closest("#inventoryElement > .item.item--overflow-beyond-slots")) {
            e.preventDefault();
            e.stopImmediatePropagation();
        }
    }, true);

    $(document).on("mouseenter", ".item", function (e) {
        if (stopTooltip) return;

        $(".tooltip").remove();
        $(document).off("mousemove.inventoryHudTooltip");

        const $el = $(this);
        const domId = $el.attr("id") || "";
        const item = $el.data("item");
        const inMainGrid = $el.closest("#inventoryElement").length > 0;
        const inFixedStrip = $el.closest("#inventoryFixedSlotsStrip").length > 0;
        let $tooltip = null;

        if ((inMainGrid || inFixedStrip) && domId === "item-money") {
            $tooltip = $("<div/>").addClass("tooltip tooltip--rich tooltip--rich-compact-hud").css("pointer-events", "none").appendTo("body");
            INVENTORY.TOOLTIP.ADD_MONEY($tooltip);
        } else if ((inMainGrid || inFixedStrip) && domId === "item-gold" && Config.UseGoldItem) {
            $tooltip = $("<div/>").addClass("tooltip tooltip--rich tooltip--rich-compact-hud").css("pointer-events", "none").appendTo("body");
            INVENTORY.TOOLTIP.ADD_GOLD($tooltip);
        } else if ((inMainGrid || inFixedStrip) && domId === "item-rol" && Config.UseRolItem && Config.AddRollItem) {
            $tooltip = $("<div/>").addClass("tooltip tooltip--rich tooltip--rich-compact-hud").css("pointer-events", "none").appendTo("body");
            INVENTORY.TOOLTIP.ADD_ROLL($tooltip);
        } else if ((inMainGrid || inFixedStrip) && domId === "item-gunbelt") {
            $tooltip = $("<div/>").addClass("tooltip tooltip--rich tooltip--rich-compact-hud").css("pointer-events", "none").appendTo("body");
            INVENTORY.TOOLTIP.ADD_GUNBELT($tooltip);
        } else if (item && typeof item === "object" && item.type != null) {
            $tooltip = $("<div/>").addClass("tooltip tooltip--rich").css("pointer-events", "none").appendTo("body");;
            INVENTORY.TOOLTIP.SETUP_CONTENT($tooltip, item, {
                isCustom: $el.closest("#secondInventoryElement").length > 0,
                group: $el.data("group"),
                count: item.count,
                limit: item.limit,
            });
            if (inMainGrid && INVENTORY.MAIN.IS_PAST_SLOT_CAP($el)) {
                const lockMsg = (LANGUAGE.labels && LANGUAGE.labels.overflowSlotLocked);
                $tooltip.append($("<div/>")
                    .addClass("tooltip-rich-overflow-locked")
                    .append($("<span/>").text(lockMsg))
                );
            }
        } else if ($el.data("tooltip")) {
            $tooltip = $("<div/>").addClass("tooltip").css("pointer-events", "none").html($el.data("tooltip")).appendTo("body");
        }

        if (!$tooltip || !$tooltip.length) return;
        INVENTORY.TOOLTIP.APPLY_LOCATION($tooltip, $el, e)
        if ($tooltip.hasClass("tooltip--rich-compact-hud")) {
            $(document).on("mousemove.inventoryHudTooltip", function (moveEv) {
                INVENTORY.TOOLTIP.STATIC_ITEMS($tooltip, moveEv);
            });
        }
    });

    $(document).on("mouseleave", ".item", function () {
        $(document).off("mousemove.inventoryHudTooltip");
        $(".tooltip").remove();
    });

    window.addEventListener('message', function (event) {

        if (event.data.action == "cacheImages") {
            UTILS.PRELOAD_IMAGES(event.data.info);
        }

        if (event.data.action == "initiate") {
            LANGUAGE = event.data.language
            LuaConfig = event.data.config
            Config.UseGoldItem = LuaConfig.UseGoldItem;
            Config.AddGoldItem = LuaConfig.AddGoldItem;
            Config.AddDollarItem = LuaConfig.AddDollarItem;
            Config.AddAmmoItem = LuaConfig.AddAmmoItem;
            Config.UseRolItem = LuaConfig.UseRolItem;
            Config.AddRollItem = LuaConfig.AddRollItem;
            Config.WeightMeasure = LuaConfig.WeightMeasure;
            Config.EnableHotbar = LuaConfig.EnableHotbar;
            Config.EnableHandCraftButton = LuaConfig.EnableHandCraftButton;
            Config.EnableSaddleButton = LuaConfig.EnableSaddleButton;
            Config.EnableWeaponAttachments = LuaConfig.EnableWeaponAttachments;
            Config.EnableSortButton = LuaConfig.EnableSortButton;
            Config.InvOrder = LuaConfig.InvOrder;
            Config.HotbarAllow = LuaConfig.HotbarAllow;
            Config.ItemRaritySlotStyle = LuaConfig.ItemRaritySlotStyle ?? Config.ItemRaritySlotStyle;
            Config.TooltipPlacement = LuaConfig.TooltipPlacement;
            Config.ManualWeaponReload = LuaConfig.ManualWeaponReload;

            Config.MainInventoryFixedSlotCount = LuaConfig.MainInventoryFixedSlotCount;

            if (Config.EnableHotbar && event.data.hotbarPos) {
                hotbarCustomPos = event.data.hotbarPos;
            }
            $("#handCraftingOpenBtn").toggle(!!Config.EnableHandCraftButton);
            $("#inventorySaddleBtn").toggle(!!Config.EnableSaddleButton);
            $("#weaponAttachmentsOpenBtn").toggle(Config.EnableWeaponAttachments);
            $("#inventorySortBtn").toggle(!!Config.EnableSortButton);
            if (!Config.EnableHandCraftButton && Config.EnableSaddleButton) {
                $("#inventorySaddleBtn").css("margin-left", "3.5vw");
            } else {
                $("#inventorySaddleBtn").css("margin-left", "");
            }
            INVENTORY.MAIN.SYNC_DROP_ZONE_LABEL();
            // Fetch the Actions configuration from Lua
            INVENTORY.MAIN.LOAD_ACTIONS_CONFIG().then(actionsConfig => {
                INVENTORY.MAIN.GEN_ACTION_BUTTONS(actionsConfig, 'carousel1', 'inventoryElement', 'dropdownButton');
                INVENTORY.MAIN.GEN_ACTION_BUTTONS(actionsConfig, 'staticCarousel', 'secondInventoryElement', 'dropdownButton1');
            }).catch(error => {
                console.error("Failed to load or process the ITEM_GROUPS configuration:", error);
            });

        }

        if (event.data.action == "reclabels") {
            ammolabels = event.data.labels
        }

        if (event.data.action == "updateammo") {
            if (event.data.ammo) {
                allplayerammo = event.data.ammo
            }
        }

        if (event.data.action == "updateStatusHud") {

            if (event.data.money || event.data.money === 0) {
                $("#money-value").text(event.data.money.toFixed(2) + " ");
            }

            if (Config.UseGoldItem) {
                if (event.data.gold || event.data.gold === 0) {
                    $("#gold-value").text(event.data.gold.toFixed(2) + " ");
                }
            }
            if (Config.UseRolItem) {
                if (event.data.rol || event.data.rol === 0) {
                    $("#rol-value").text(event.data.rol.toFixed(2) + " ");
                }
            }


            if (event.data.id) {
                $("#id-value").text("ID " + event.data.id);
            }

        }

        //main inv update weight
        if (event.data.action == "changecheck") {
            checkxy = event.data.check
            infoxy = event.data.info

            const $c = $("#check .inv-weight-text");
            if ($c.length) {
                $c.text(`${checkxy}/${infoxy} ${Config.WeightMeasure}`);
            }
            UTILS.APPLY_INV_CAPACITY_WARNING($("#check"), checkxy, infoxy);
        }

        //main inv
        if (event.data.action == "display") {
            CRAFTING.CLOSE();
            type = event.data.type;
            $("body").addClass("inventory-hud-active");
            $("body").toggleClass("inventory-open", type === "main");
            $("body").toggleClass("main-inv-with-secondary", event.data.type !== "main");
            $("#handCraftingOpenBtn").prop("disabled", type !== "main" || !Config.EnableHandCraftButton);
            $("#inventorySaddleBtn").prop("disabled", type !== "main" || !Config.EnableSaddleButton);
            $("#weaponAttachmentsOpenBtn").prop("disabled", type !== "main" || Config.EnableWeaponAttachments !== true);
            $("#inventorySortBtn").prop("disabled", type !== "main");
            if (!Config.EnableHotbar) {
                $("#hotbarHud").addClass("hotbar-hud--hidden");
            }
            HOTBAR.VISIBILITY.REFRESH();
            stopTooltip = false;
            INVENTORY.MAIN.MOVE_INVENTORY_HUD("main");
            if (event.data.type != 'main') {
                INVENTORY.MAIN.MOVE_INVENTORY_HUD("second");
            }

            $("#inventoryHud").stop(true, true);
            $("#inventoryHud").fadeIn(200, function () {
                INVENTORY.MAIN.SCHEDULE_MAIN_GROUP_STRIP();
                INVENTORY.SECONDARY.SCHEDULE_GROUP_STRIP();
            });

            $("#inv-controls-hint").fadeIn(200);
            UTILS.UPDATE_HINT_VISIBILITY();
            $(".controls").remove();
            $("#check").remove();
            $("#inventoryHud").append(
                `<div class='controls'><div class='controls-center'><input type='text' id='search' placeholder='${LANGUAGE.inventorysearch}'/></div></div><div id='check' class='inv-weight inv-weight-main' role='status'><span class='inv-weight-text'>${checkxy}/${infoxy} ${Config.WeightMeasure}</span></div>`
            );
            UTILS.APPLY_INV_CAPACITY_WARNING($("#check"), checkxy, infoxy);
            if (LANGUAGE && LANGUAGE.inventoryclose) {
                $("#close .mainButton-close__label").text(LANGUAGE.inventoryclose);
                $("#close").attr("title", LANGUAGE.inventoryclose).attr("aria-label", LANGUAGE.inventoryclose);
            }

            $("#search").bind("input", function () {
                var searchFor = $("#search").val().toLowerCase();
                $("#inventoryElement .item").each(function () {
                    var label = $(this).data("label");
                    if (label) {
                        label = label.toLowerCase();
                        if (label.indexOf(searchFor) < 0) {
                            $(this).hide();
                        } else {
                            $(this).show();
                        }
                    }
                });
            });

            if (event.data.type == "player") {
                playerId = event.data.id;

                INVENTORY.SECONDARY.INIT(event.data.title, event.data.capacity)
            }

            if (event.data.type == "custom") {
                customId = event.data.id;
                INVENTORY.SECONDARY.INIT(event.data.title, event.data.capacity, event.data.weight)
            }

            if (event.data.type == "horse") {
                horseid = event.data.horseid;
                INVENTORY.SECONDARY.INIT(event.data.title, event.data.capacity)
            }

            if (event.data.type == "cart") {
                wagonid = event.data.wagonid;
                INVENTORY.SECONDARY.INIT(event.data.title, event.data.capacity)
            }

            if (event.data.type == "house") {
                houseId = event.data.houseId;
                INVENTORY.SECONDARY.INIT(event.data.title, event.data.capacity)
            }
            if (event.data.type == "hideout") {
                hideoutId = event.data.hideoutId;
                INVENTORY.SECONDARY.INIT(event.data.title, event.data.capacity)
            }
            if (event.data.type == "clan") {
                clanid = event.data.clanid;
                INVENTORY.SECONDARY.INIT(event.data.title, event.data.capacity)
            }
            if (event.data.type == "store") {
                StoreId = event.data.StoreId;
                geninfo = event.data.geninfo;
                INVENTORY.SECONDARY.INIT(event.data.title, event.data.capacity)
            }
            if (event.data.type == "steal") {
                stealid = event.data.stealId;
                INVENTORY.SECONDARY.INIT(event.data.title, event.data.capacity)
            }
            if (event.data.type == "Container") {
                Containerid = event.data.Containerid;
                INVENTORY.SECONDARY.INIT(event.data.title, event.data.capacity)
            }


            disabled = false;

            if (event.data.autofocus == true) {
                $(document).on('keydown', function (event) {
                    if (!(event.target && event.target.id === 'secondarysearch')) {
                        $("#search").focus();
                    }
                });
            }

        } else if (event.data.action == "hide") {
            CRAFTING.CLOSE();
            type = "normal";
            $("body").removeClass("main-inv-with-secondary");
            HOTBAR.VISIBILITY.REFRESH();
            INVENTORY.MAIN.CLEAR_INV_SORT();
            $("body").removeClass("inventory-open");
            $('.tooltip').remove();
            const el = document.getElementById("carousel1");
            if (el) {
                el.style.scrollBehavior = "auto";
                el.scrollLeft = 0;
            }
            const secStrip = document.getElementById("staticCarousel");
            if (secStrip) {
                secStrip.style.scrollBehavior = "auto";
                secStrip.scrollLeft = 0;
            }
            $("#inventoryHud").fadeOut(function () {
                if (type !== "normal") return;
                $("body").removeClass("inventory-open").removeClass("inventory-hud-active").removeClass("main-inv-with-secondary");
                $("#handCraftingOpenBtn, #inventorySaddleBtn, #weaponAttachmentsOpenBtn").prop("disabled", false);
            });
            $(".controls").fadeOut();
            $(".site-cm-box").remove();
            $("#secondInventoryHud").fadeOut();
            $("#inv-controls-hint").fadeOut(150);
            $(".controls").fadeOut();
            $(".site-cm-box").remove();
            $("#sortConfirmPopup").hide();
            dialog.close();
            stopTooltip = true;
        } else if (event.data.action == "setItems") {
            TIME_NOW = event.data.timenow

            if (Config.EnableHotbar && event.data.hotbarSlots) {
                HOTBAR.SYNC_DATA(event.data.hotbarSlots);
            }

            INVENTORY.MAIN.INVENTORY_SETUP(event.data.itemList, {
                slots: event.data.slotLayout,
                slotCount: event.data.slotCount,
            });

            INVENTORY.MAIN.CLEAR_INV_SORT();
            INVENTORY.MAIN.INIT_INV_SORT();

            if (Config.EnableHandCraftButton && $("#handCraftingPanel").is(":visible")) {
                CRAFTING.REFRESH_REQUIREMENTS();
            }

            if ($("#inventoryHud").is(":visible")) {
                $("#inv-controls-hint").fadeIn(200);
                UTILS.UPDATE_HINT_VISIBILITY();
            }

            if (type != "main") {
                INVENTORY.MAIN.INIT_CROSS_INV_DRAG($("#secondInventoryElement .item").filter(function () {
                    return !!$(this).data("item");
                }));
            }
        } else if (event.data.action == "setSecondInventoryItems") {
            $("#inv-controls-hint").fadeIn(200);
            UTILS.UPDATE_HINT_VISIBILITY();

            INVENTORY.SECONDARY.SETUP(event.data.itemList, event.data.info);
            INVENTORY.MAIN.INIT_CROSS_INV_DRAG($("#secondInventoryElement .item").filter(function () {
                return !!$(this).data("item");
            }));

            INVENTORY.SECONDARY.SCHEDULE_GROUP_STRIP();

            let l = event.data.itemList.length
            let itemlist = event.data.itemList
            let total = 0
            let p = 0
            for (p; p < l; p++) {
                total += Number(itemlist[p].count)
            }

            //amount of items in Inventory
            INVENTORY.SECONDARY.SET_CURRENT_CAPACITY(total);
        } else if (event.data.action == "mainItemUpdate") {
            INVENTORY.MAIN.MAIN_UPDATE_ITEM(event.data.item);
            WEAPON_ATTACHMENTS.MAIN_ITEM_UPDATE(event.data.item);
        } else if (event.data.action == "mainItemRemoved") {
            INVENTORY.MAIN.MAIN_REMOVE_ITEM(event.data.id, event.data.itemType);
        } else if (event.data.action == "weaponUsedUpdate") {
            INVENTORY.MAIN.WEAPON_USED_UPDATE(event.data.id, event.data.used, event.data.used2, event.data.weaponLiveStatus);
        } else if (event.data.action == "secondaryItemAdded") {
            INVENTORY.SECONDARY.ITEM_ADDED(event.data.item);
        } else if (event.data.action == "secondaryItemRemoved") {
            INVENTORY.SECONDARY.ITEM_REMOVED(event.data.id, event.data.itemType);
        } else if (event.data.action == "secondaryItemUpdated") {
            INVENTORY.SECONDARY.ITEM_UPDATED(event.data.id, event.data.count);
        } else if (event.data.action == "hotbarSync") {
            HOTBAR.SYNC_DATA(event.data.slots);
        } else if (event.data.action == "hotbarGame") {
            HOTBAR.APPLY_GAME_VISIBLE(!!event.data.visible);
        }
    });

    window.addEventListener("offline", function () {
        INVENTORY.CLOSE()
    });

});