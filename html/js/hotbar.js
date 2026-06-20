const HOTBAR_COUNT = 5;
let hotbarGameVisible = false;
let hotbarSaveTimer = null;
let hotbarCustomPos = null;
let hotbarEditMode = false;
let hotbarSlotData = [null, null, null, null, null];

const HOTBAR = {
    UTIL: {
        CLONE_ITEM: function (item) {
            try {
                return JSON.parse(JSON.stringify(item));
            } catch (e) {
                return null;
            }
        },

        PERSIST_FIELDS: function (e) {
            if (!e || e.id == null || !e.type) return null;
            const name = e.name;
            return {
                type: e.type,
                id: e.id,
                name: String(name),
                hash: e.hash != null ? e.hash : 0,
            };
        },

        NORMALIZE_PAYLOAD_SLOTS: function (slots) {
            if (!slots) return [];
            if (Array.isArray(slots)) return slots;

            const keys = Object.keys(slots).sort((a, b) => Number(a) - Number(b));
            return keys.map(function (k) {
                return slots[k];
            });
        },

        CELL_AT: function (raw, i) {
            if (!raw) return null;
            if (Array.isArray(raw)) return raw[i] != null ? raw[i] : raw[String(i)];

            return raw[i] != null ? raw[i] : raw[i + 1] != null ? raw[i + 1] : raw[String(i + 1)];
        },
    },

    ICON: {
        ADD_IMAGE: function (entry) {
            if (!entry) return "";
            const key = (entry.metadata?.image || entry.name).toString();
            const u = imageCache[key];
            const iconLayerRaw = (u || `url("img/items/${key}.png")`).toString().trim();
            const iconLayer = iconLayerRaw.replace(/;+\s*$/, "") || 'url("img/items/placeholder.png")';
            return ("background-image: " + iconLayer + "; background-size: contain; background-repeat: no-repeat; background-position: center;");
        },
    },

    IS_ITEM_ON_HOTBAR: function (item) {
        if (!INVENTORY.MAIN.CAN_ASSIGN_TO_HOTBAR(item)) return false;

        const k = String(item.type) + ":" + String(item.id);
        for (let i = 0; i < HOTBAR_COUNT; i++) {
            const e = hotbarSlotData[i];
            if (e && e.id != null && e.type && String(e.type) + ":" + String(e.id) === k) return true;
        }
        return false;
    },

    SYNC_DATA: function (slotsPayload) {
        if (!Config.EnableHotbar) return;
        const raw = HOTBAR.UTIL.NORMALIZE_PAYLOAD_SLOTS(slotsPayload);

        hotbarSlotData = Array.from({ length: HOTBAR_COUNT }, function (_, i) {
            const cell = HOTBAR.UTIL.CELL_AT(raw, i);
            if (cell && cell.occupied && cell.id != null && cell.type && cell.name) {
                const entry = Object.assign({}, cell);
                delete entry.occupied;
                delete entry.index;
                entry.used = !!cell.used;
                entry.used2 = !!cell.used2;
                return entry;
            }
            return null;
        });

        HOTBAR.REFRESH_SLOT_VISUALS();
        HOTBAR.INIT_MAIN_DND();
    },

    REFRESH_SLOT_VISUALS: function () {
        for (let i = 0; i < HOTBAR_COUNT; i++) {
            const $slot = $(`.hotbar-slot[data-hotbar-index="${i}"]`);
            const $icon = $slot.find(".hotbar-slot-icon");
            const d = hotbarSlotData[i];
            $slot.toggleClass("hotbar-slot-filled", !!d);

            if ($icon.data("ui-draggable")) {
                try {
                    $icon.draggable("destroy");
                } catch (e) {
                    /* ignore */
                }
            }
            $icon.find(".count, .equipped-icon, .hotbar-weapon-bullets").remove();
            if (d) {
                $icon
                    .addClass("hotbar-slot-icon-filled")
                    .attr("data-occupied", "1")
                    .attr("style", HOTBAR.ICON.ADD_IMAGE(d));
                if (d.type === "item_standard" && d.count != null) {
                    $icon.append(`<div class="count"><span style="color:Black">${d.count}</span></div>`);
                }
                if (d.type === "item_weapon") {
                    const bullets = INVENTORY.WEAPON.GET_AMMO_COUNT(d);
                    if (INVENTORY.WEAPON.SHOW_AMMO_UI(d)) {
                        $icon.append(
                            '<div class="hotbar-weapon-bullets">' +
                            '<img class="weapon-ammo-count-icon" src="img/ammo.png" alt="" loading="lazy" ' +
                            "onerror=\"this.onerror=null;this.src='imgs/ammo.png';\"/>" +
                            "<span>" +
                            UTILS.ESCAPE_HTML(String(bullets)) +
                            "</span></div>"
                        );
                    }
                    if (d.used || d.used2) {
                        $icon.append(`<div class="equipped-icon"></div>`);
                    }
                }
            } else {
                $icon.removeClass("hotbar-slot-icon-filled").attr("data-occupied", "0").removeAttr("style");
            }
        }
    },

    SAVE: function () {
        clearTimeout(hotbarSaveTimer);

        hotbarSaveTimer = setTimeout(function () {
            const slots = [];
            for (let i = 0; i < HOTBAR_COUNT; i++) {
                slots.push(HOTBAR.UTIL.PERSIST_FIELDS(hotbarSlotData[i]));
            }
            $.post(`https://${GetParentResourceName()}/SaveHotbar`, JSON.stringify({ slots: slots }));
        }, 120);
    },

    MAIN_INVENTORY_UI_ACTIVE: function () {
        if (type === "normal") return false;
        if (type === "main") return true;
        return true;
    },

    REFRESH_MAIN_INV_AND_DND: function () {
        if (HOTBAR.MAIN_INVENTORY_UI_ACTIVE()) {

            INVENTORY.MAIN.CLEAR_INV_SORT();
            INVENTORY.MAIN.INIT_INV_SORT();
            HOTBAR.INIT_MAIN_DND();
        }
    },

    ASSIGN_SLOT: function (slotIndex0, item, $sourceRow) {
        if (!INVENTORY.MAIN.CAN_ASSIGN_TO_HOTBAR(item)) return;

        const stored = HOTBAR.UTIL.CLONE_ITEM(item);
        if (!stored) return;

        const displaced = hotbarSlotData[slotIndex0];
        hotbarSlotData[slotIndex0] = stored;
        const srcEl = $sourceRow && $sourceRow.length && $sourceRow.closest("#inventoryElement").length ? $sourceRow[0] : null;
        const displacedClone = displaced ? HOTBAR.UTIL.CLONE_ITEM(displaced) : null;

        setTimeout(function () {
            HOTBAR.REFRESH_SLOT_VISUALS();
            if (srcEl) {
                const $src = $(srcEl);
                if ($src.length && $src.closest("#inventoryElement").length) {
                    if (displacedClone) {
                        INVENTORY.MAIN.RENDER_ITEM_CELL(displacedClone, $src);
                    } else {
                        $src.replaceWith($('<div class="item" data-group="0" data-sortable="true"></div>'));
                    }
                }
            }

            HOTBAR.SAVE();
            INVENTORY.MAIN.QUEUE_LAYOUT_SAVE();
            HOTBAR.REFRESH_MAIN_INV_AND_DND();
        }, 0);
    },

    SWAP_SLOTS: function (a, b) {
        const data = hotbarSlotData;
        const entry = data[a];
        data[a] = data[b];
        data[b] = entry;

        setTimeout(function () {
            HOTBAR.REFRESH_SLOT_VISUALS();
            HOTBAR.SAVE();
            HOTBAR.INIT_MAIN_DND();
        }, 0);
    },

    RELEASE_TO_MAIN_EMPTY_CELL: function (hotbarIndex0, $emptyCell) {
        if (hotbarIndex0 < 0 || hotbarIndex0 >= HOTBAR_COUNT) return;
        if (!$emptyCell || !$emptyCell.length) return;
        if (!INVENTORY.MAIN.IS_MAIN_EMPTY_SLOT($emptyCell)) return;

        const entry = hotbarSlotData[hotbarIndex0];
        if (!entry) return;

        const renderItem = HOTBAR.UTIL.CLONE_ITEM(entry);
        if (!renderItem) return;

        const emptyEl = $emptyCell[0];

        setTimeout(function () {
            hotbarSlotData[hotbarIndex0] = null;
            HOTBAR.REFRESH_SLOT_VISUALS();
            const $cell = $(emptyEl);
            if ($cell.length && INVENTORY.MAIN.IS_MAIN_EMPTY_SLOT($cell)) {
                INVENTORY.MAIN.RENDER_ITEM_CELL(renderItem, $cell);
            }
            HOTBAR.SAVE();
            HOTBAR.REFRESH_MAIN_INV_AND_DND();
            INVENTORY.MAIN.QUEUE_LAYOUT_SAVE();
        }, 0);
    },

    DND: {
        INIT_HUD: function () {
            $(".hotbar-slot").each(function () {
                const $slot = $(this);
                const toIdx = parseInt($slot.attr("data-hotbar-index"), 10);
                $slot.droppable({
                    accept: function ($draggable) {
                        if ($draggable.closest("#secondInventoryElement").length) return false;
                        if ($draggable.hasClass("hotbar-slot-icon") && $draggable.attr("data-occupied") === "1")
                            return true;

                        if ($draggable.closest("#inventoryElement").length && $draggable.hasClass("item")) {
                            if (INVENTORY.MAIN.IS_PAST_SLOT_CAP($draggable)) {
                                return false;
                            }

                            const item = $draggable.data("item");
                            return INVENTORY.MAIN.CAN_ASSIGN_TO_HOTBAR(item);
                        }

                        return false;
                    },
                    tolerance: "pointer",
                    greedy: true,
                    drop: function (_, ui) {
                        const draggable = ui.draggable;
                        if (draggable.closest("#secondInventoryElement").length) return;
                        if (draggable.hasClass("hotbar-slot-icon")) {
                            const fromIdx = parseInt(draggable.closest(".hotbar-slot").attr("data-hotbar-index"), 10);

                            if (!Number.isNaN(fromIdx) && !Number.isNaN(toIdx) && fromIdx !== toIdx) {
                                HOTBAR.SWAP_SLOTS(fromIdx, toIdx);
                            }
                            return;
                        }

                        const item = draggable.data("item");
                        if (draggable.closest("#inventoryElement").length && draggable.hasClass("item")) {
                            if (INVENTORY.MAIN.IS_PAST_SLOT_CAP(draggable)) {
                                return;
                            }
                        }

                        if (INVENTORY.MAIN.CAN_ASSIGN_TO_HOTBAR(item)) {
                            const $row = draggable.hasClass("item") ? draggable : draggable.closest("#inventoryElement > .item");
                            if ($row.length && $row.closest("#inventoryElement").length) {
                                $row.data("invDropAccepted", true);
                            }

                            const $src = $row.length ? $row : null;
                            setTimeout(function () {
                                HOTBAR.ASSIGN_SLOT(toIdx, item, $src);
                            }, 0);
                        }
                    },
                });
                const $icon = $slot.find(".hotbar-slot-icon");
                if ($icon.attr("data-occupied") === "1") {
                    $icon.draggable({
                        helper: function () {
                            const $el = $(this);
                            const $parentSlot = $el.closest(".hotbar-slot");
                            const slotLayer = $parentSlot.hasClass("hotbar-slot-filled") ? 'url("img/slotfilled.png")' : 'url("img/slot.png")';
                            let iconLayer = ($el.css("background-image") || "").trim().replace(/;+\s*$/, "");
                            if (!iconLayer || iconLayer === "none") {
                                iconLayer = 'url("img/items/placeholder.png")';
                            }
                            return $('<div class="hotbar-drag-helper"/>').css({
                                backgroundImage: iconLayer + ", " + slotLayer,
                                backgroundSize: "contain, 100% 100%",
                                backgroundRepeat: "no-repeat, no-repeat",
                                backgroundPosition: "center, center",
                            });
                        },
                        appendTo: "body",
                        zIndex: 99999,
                        revert: "invalid",
                        scroll: false,
                        distance: 6,
                        containment: "document",
                        drag: function (event) {
                            const $el = $(this);
                            INVENTORY.MAIN.MAIN_INV_AUTO_SCROLL_DRAG(event);
                            if (event.clientX != null && event.clientY != null) {
                                $el.data("invHotbarPointer", { x: event.clientX, y: event.clientY });
                            }
                        },
                        start: function (event) {
                            const $el = $(this);
                            const ev0 = event && event.originalEvent ? event.originalEvent : event;
                            if (ev0 && ev0.clientX != null && ev0.clientY != null) {
                                $el.data("invHotbarPointer", { x: ev0.clientX, y: ev0.clientY });
                            }
                            stopTooltip = true;
                            $(".tooltip").remove();
                            $el.css("opacity", 0.35);
                        },
                        stop: function () {
                            const $el = $(this);
                            $el.removeData("invHotbarPointer");
                            stopTooltip = false;
                            $el.css("opacity", "");
                        },
                    });
                }
            });
        },

        TEARDOWN_HUD: function () {
            $(".hotbar-slot").each(function () {
                const $slot = $(this);
                if ($slot.data("ui-droppable")) {
                    try {
                        $slot.droppable("destroy");
                    } catch (e) {
                        /* ignore */
                    }
                }
            });
            $(".hotbar-slot-icon").each(function () {
                const $icon = $(this);
                if ($icon.data("ui-draggable")) {
                    try {
                        $icon.draggable("destroy");
                    } catch (e) {
                        /* ignore */
                    }
                }
            });
        },
    },

    POSITION: {
        APPLY_CUSTOM: function (pos) {
            if (!pos) return;
            $("#hotbarHud").css({
                left: pos.left + "%",
                top: pos.top + "%",
                bottom: "auto",
                transform: "none",
            });
        },

        CLEAR_CUSTOM: function () {
            $("#hotbarHud").css({ left: "", top: "", bottom: "", transform: "" });
        },
    },

    VISIBILITY: {
        REFRESH: function () {
            if(!Config.EnableHotbar) return;
            const inventoryNuiOpen = type !== "normal";
            const show = hotbarEditMode || inventoryNuiOpen || hotbarGameVisible;
            if (show) {
                $("#hotbarHud").removeClass("hotbar-hud--hidden");
            } else {
                $("#hotbarHud").addClass("hotbar-hud--hidden");
            }
            $("#hotbarHud").toggleClass("hotbar-hud--with-inventory", inventoryNuiOpen && !hotbarEditMode);
            if (!hotbarEditMode) {
                if (!inventoryNuiOpen && hotbarCustomPos) {
                    HOTBAR.POSITION.APPLY_CUSTOM(hotbarCustomPos);
                } else {
                    HOTBAR.POSITION.CLEAR_CUSTOM();
                }
            }
        },
    },

    INIT_MAIN_DND: function () {
        if (!Config.EnableHotbar) return;

        HOTBAR.DND.TEARDOWN_HUD();

        if (HOTBAR.MAIN_INVENTORY_UI_ACTIVE()) {
            HOTBAR.DND.INIT_HUD();
        }
    },

    APPLY_GAME_VISIBLE: function (visible) {
        if (!Config.EnableHotbar) return;

        hotbarGameVisible = !!visible;
        HOTBAR.VISIBILITY.REFRESH();
    },

    EDIT: {
        ENTER: function () {
            if (hotbarEditMode) return;
            hotbarEditMode = true;
            const $hud = $("#hotbarHud");
            $hud.removeClass("hotbar-hud--hidden").removeClass("hotbar-hud--with-inventory");
            const rect = $hud[0].getBoundingClientRect();
            const leftPct = (rect.left / window.innerWidth) * 100;
            const topPct = (rect.top / window.innerHeight) * 100;
            $hud.css({ left: leftPct + "%", top: topPct + "%", bottom: "auto", transform: "none" });
            $hud.addClass("hotbar-hud--editing");
            $hud.draggable({ containment: "window", scroll: false, cursor: "grabbing" });
            $("body").append(
                '<div id="hotbar-edit-hint">DRAG HOTBAR &bull; ENTER TO SAVE &bull; ESC TO CANCEL</div>'
            );

            $(document).on("keydown.hotbarEdit", function (e) {
                if (e.key === "Enter") {
                    HOTBAR.EDIT.EXIT(true);
                } else if (e.key === "Escape") {
                    HOTBAR.EDIT.EXIT(false);
                }
            });
        },

        EXIT: function (save) {
            if (!hotbarEditMode) return;
            hotbarEditMode = false;
            const $hud = $("#hotbarHud");
            if ($hud.data("ui-draggable")) {
                try {
                    $hud.draggable("destroy");
                } catch (e) {
                    /* ignore */
                }
            }

            $hud.removeClass("hotbar-hud--editing");
            $("#hotbar-edit-hint").remove();
            $(document).off("keydown.hotbarEdit");
            if (save) {
                const rect = $hud[0].getBoundingClientRect();
                const leftPct = (rect.left / window.innerWidth) * 100;
                const topPct = (rect.top / window.innerHeight) * 100;
                hotbarCustomPos = { left: leftPct, top: topPct };
                $.post(
                    `https://${GetParentResourceName()}/SaveHotbarPosition`,
                    JSON.stringify({ left: leftPct, top: topPct })
                );
            }
            $.post(`https://${GetParentResourceName()}/NUIFocusOff`, JSON.stringify({}));
            HOTBAR.VISIBILITY.REFRESH();
        },
    },
};

window.addEventListener("message", function (event) {
    const data = event.data;
    if (!data.action) return;
    if (!Config.EnableHotbar) return;

    if (data.action === "hotbarSetPos") {
        if (data.left != null && data.top != null) {
            hotbarCustomPos = { left: data.left, top: data.top };
            HOTBAR.VISIBILITY.REFRESH();
        }

    } else if (data.action === "hotbarEditPos") {
        HOTBAR.EDIT.ENTER();
    }
});
