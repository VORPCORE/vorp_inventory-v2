INVENTORY.SECONDARY = {
    MIN_SLOTS: 24,

    ACTION_TAKE_LIST: {
        custom: { action: "TakeFromCustom", id: () => customId, customtype: "id" },
        player: { action: "TakeFromPlayer", id: () => playerId, customtype: "player" },
        cart: { action: "TakeFromCart", id: () => wagonid, customtype: "wagon" },
        house: { action: "TakeFromHouse", id: () => houseId, customtype: "house" },
        hideout: { action: "TakeFromHideout", id: () => hideoutId, customtype: "hideout" },
        clan: { action: "TakeFromClan", id: () => clanid, customtype: "clan" },
        steal: { action: "TakeFromsteal", id: () => stealid, customtype: "steal" },
        Container: { action: "TakeFromContainer", id: () => Containerid, customtype: "Container" },
        horse: { action: "TakeFromHorse", id: () => horseid, customtype: "horse" },
    },

    ACTION_MOVE_LIST: {
        custom: { action: "MoveToCustom", id: () => customId, customtype: "id" },
        player: { action: "MoveToPlayer", id: () => playerId, customtype: "player" },
        cart: { action: "MoveToCart", id: () => wagonid, customtype: "wagon" },
        house: { action: "MoveToHouse", id: () => houseId, customtype: "house" },
        hideout: { action: "MoveToHideout", id: () => hideoutId, customtype: "hideout" },
        clan: { action: "MoveToClan", id: () => clanid, customtype: "clan" },
        steal: { action: "MoveTosteal", id: () => stealid, customtype: "steal" },
        Container: { action: "MoveToContainer", id: () => Containerid, customtype: "Container" },
        horse: { action: "MoveToHorse", id: () => horseid, customtype: "horse" },
    },

    POST_ACTION_POST_QTY: function (eventName, itemData, id, propertyName, qty, info) {
        if (isValidating) return;

        UTILS.PROCESS_EVENT_VALIDATION();

        $.post(
            `https://${GetParentResourceName()}/${eventName}`,
            JSON.stringify({
                item: itemData,
                type: itemData.type,
                number: qty,
                [propertyName]: id,
                info: info,
            })
        );
    },

    POST_ACTION: function (eventName, itemData, id, propertyName, info) {
        INVENTORY.DISABLE(500);
        if (itemData.type != "item_weapon") {
            if (itemData.count === 1 || isShiftActive === true) {
                const qty = isShiftActive ? itemData.count : 1;
                this.POST_ACTION_POST_QTY(eventName, itemData, id, propertyName, qty, info);
                return;
            }

            if (altDragActive && itemData.count > 1) {
                const qty = Math.ceil(itemData.count / 2);
                altDragActive = false;
                this.POST_ACTION_POST_QTY(eventName, itemData, id, propertyName, qty, info);
                return;
            }

            const self = this;
            dialog.prompt({
                title: LANGUAGE.prompttitle,
                button: LANGUAGE.promptaccept,
                required: true,
                item: itemData,
                type: itemData.type,
                input: {
                    type: "number",
                    autofocus: "true",
                },

                validate: function (value) {
                    if (!value || value <= 0 || value > Config.MaxItemTransferAmount || !UTILS.IS_INT(value)) {
                        $.post(`https://${GetParentResourceName()}/TransferLimitExceeded`, JSON.stringify({
                            max: Config.MaxItemTransferAmount,
                        }));

                        dialog.close();
                    } else {
                        self.POST_ACTION_POST_QTY(eventName, itemData, id, propertyName, value, info);
                    }
                },
            });
        } else {
            this.POST_ACTION_POST_QTY(eventName, itemData, id, propertyName, 1, info);
        }
    },

    TAKE_FROM_STORE: function (itemData, qty) {
        if (isValidating) return;

        UTILS.PROCESS_EVENT_VALIDATION();

        $.post(
            `https://${GetParentResourceName()}/TakeFromStore`,
            JSON.stringify({
                item: itemData,
                type: itemData.type,
                number: qty,
                price: itemData.price,
                geninfo: geninfo,
                store: StoreId,
            })
        );
    },

    MOVE_TO_STORE: function (itemData, qty) {
        if (isValidating) return;

        UTILS.PROCESS_EVENT_VALIDATION();

        $.post(
            `https://${GetParentResourceName()}/MoveToStore`,
            JSON.stringify({
                item: itemData,
                type: itemData.type,
                number: qty,
                geninfo: geninfo,
                store: StoreId,
            })
        );
    },

    MOVE_TO_STORE_PRICED: function (itemData, qty, price) {
        if (isValidating) return;

        UTILS.PROCESS_EVENT_VALIDATION();

        $.post(
            `https://${GetParentResourceName()}/MoveToStore`,
            JSON.stringify({
                item: itemData,
                type: itemData.type,
                number: qty,
                price: price,
                geninfo: geninfo,
                store: StoreId,
            })
        );
    },

    OPEN_STORE_PRICE_DIALOG: function (itemData, qty) {
        if (isValidating) return;

        UTILS.PROCESS_EVENT_VALIDATION();

        const self = this;
        dialog.prompt({
            title: LANGUAGE.prompttitle2,
            button: LANGUAGE.promptaccept,
            required: true,
            item: itemData,
            type: itemData.type,
            input: {
                type: "number",
                autofocus: "true",
            },
            validate: function (value2) {
                if (!value2) {
                    dialog.close();
                    return;
                }

                self.MOVE_TO_STORE_PRICED(itemData, qty, value2);
            },
        });
    },

    INIT_HANDLERS: function () {
        const S = INVENTORY.SECONDARY;

        $(document).on("click.shiftQuickMove", "#inventoryElement .item", function (e) {
            if (!e.shiftKey) return;
            if (type === "normal" || type === "main") return;
            const itemData = $(this).data("item");
            if (!itemData) return;
            const info = $("#secondInventoryElement").data("info");
            if (type in S.ACTION_MOVE_LIST) {
                const { action, id, customtype } = S.ACTION_MOVE_LIST[type];
                S.POST_ACTION(action, itemData, id(), customtype, info);
            } else if (type === "store") {
                INVENTORY.DISABLE(500);
                if (itemData.type !== "item_weapon") {
                    const qty = itemData.count;
                    if (geninfo.isowner != 0) {
                        S.OPEN_STORE_PRICE_DIALOG(itemData, qty);
                    } else {
                        S.MOVE_TO_STORE(itemData, qty);
                    }
                } else {
                    S.OPEN_STORE_PRICE_DIALOG(itemData, 1);
                }
            }
        });

        $(document).on("click.shiftQuickTake", "#secondInventoryElement .item", function (e) {
            if (!e.shiftKey) return;
            if (type === "normal" || type === "main") return;

            const itemData = $(this).data("item");
            if (!itemData) return;

            const info = $("#secondInventoryElement").data("info");
            if (type in S.ACTION_TAKE_LIST) {
                const { action, id, customtype } = S.ACTION_TAKE_LIST[type];
                S.POST_ACTION(action, itemData, id(), customtype, info);
            } else if (type === "store") {
                INVENTORY.DISABLE(500);
                const quantity = itemData.type !== "item_weapon" ? itemData.count : 1;
                S.TAKE_FROM_STORE(itemData, quantity);
            }
        });

        $("#inventoryElement").droppable({
            drop: function (_, ui) {
                itemData = ui.draggable.data("item");
                itemInventory = ui.draggable.data("inventory");
                var info = $("#secondInventoryElement").data("info");

                if (itemInventory === "second") {
                    if (type in S.ACTION_TAKE_LIST) {
                        const { action, id, customtype } = S.ACTION_TAKE_LIST[type];
                        const Id = id();
                        S.POST_ACTION(action, itemData, Id, customtype, info);
                    } else if (type === "store") {
                        INVENTORY.DISABLE(500);
                        if (itemData.type != "item_weapon") {
                            if (itemData.count === 1 || isShiftActive === true) {
                                const qty = isShiftActive ? itemData.count : 1;
                                S.TAKE_FROM_STORE(itemData, qty);
                                return;
                            }

                            dialog.prompt({
                                title: LANGUAGE.prompttitle,
                                button: LANGUAGE.promptaccept,
                                required: true,
                                item: itemData,
                                type: itemData.type,
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

                                    S.TAKE_FROM_STORE(itemData, value);
                                },
                            });
                        } else {
                            S.TAKE_FROM_STORE(itemData, 1);
                        }
                    }
                }
            },
        });

        $("#secondInventoryElement").droppable({
            drop: function (_, ui) {
                itemData = ui.draggable.data("item");
                itemInventory = ui.draggable.data("inventory");
                var info = $(this).data("info");
                const $drag = ui.draggable;

                if (itemInventory === "main") {
                    if (type in S.ACTION_MOVE_LIST || type === "store") {
                        $drag.data("invDropAccepted", true);
                    }
                    if (type in S.ACTION_MOVE_LIST) {
                        const { action, id, customtype } = S.ACTION_MOVE_LIST[type];
                        const Id = id();
                        S.POST_ACTION(action, itemData, Id, customtype, info);
                    } else if (type === "store") {
                        INVENTORY.DISABLE(500);

                        if (itemData.type != "item_weapon") {
                            if (itemData.count === 1 || isShiftActive === true) {
                                const qty = isShiftActive ? itemData.count : 1;
                                if (geninfo.isowner != 0) {
                                    S.OPEN_STORE_PRICE_DIALOG(itemData, qty);
                                } else {
                                    S.MOVE_TO_STORE(itemData, qty);
                                }
                                return;
                            }

                            dialog.prompt({
                                title: LANGUAGE.prompttitle,
                                button: LANGUAGE.promptaccept,
                                required: true,
                                item: itemData,
                                type: itemData.type,
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

                                    if (geninfo.isowner != 0) {
                                        S.OPEN_STORE_PRICE_DIALOG(itemData, value);
                                    } else {
                                        S.MOVE_TO_STORE(itemData, value);
                                    }
                                },
                            });
                        } else {
                            const qty = 1;
                            if (geninfo.isowner != 0) {
                                S.OPEN_STORE_PRICE_DIALOG(itemData, qty);
                            } else {
                                S.MOVE_TO_STORE(itemData, qty);
                            }
                        }
                    }
                }
            },
        });
    },

    BIND_ITEM_DATA: function (item, index) {
        $("#item-" + index).data("item", item);
        $("#item-" + index).data("inventory", "second");
    },

    LOAD_ITEM_CELL: function (item, index, group, count, limit) {
        if (item.type === "item_weapon") return;

        const { tooltipData, degradation, image, label, weight, durability } = UTILS.GET_ITEM_METADATA_INFO(item, true);
        const itemWeight = UTILS.GET_ITEM_WEIGHT(weight, 1);
        const groupKey = UTILS.GET_GROUP_KEY(group);
        const { tooltipContent, url } = INVENTORY.TOOLTIP.GET_CONTENT(image, groupKey, group, limit, itemWeight, degradation, tooltipData, count, durability);
        const iconOpacityExtra = UTILS.ITEM_ICON_OPACITY_EXTRA(item);

        $("#secondInventoryElement").append(
            `<div data-label='${label}' data-group='${group}' class='item item-filled' id="item-${index}" data-tooltip='${tooltipContent}'><span class='item-inv-icon' style='${UTILS.INVENTORY_SLOT_BACKGROUND_STYLE(url, "4.5vw", "7.7vh", iconOpacityExtra)}'></span>${count > 0 ? `<div class='count'><span style='color:Black'>${count}</span></div>` : ``}</div>`
        );

        UTILS.APPLY_RARITY_SLOT_CLASSES($("#item-" + index), item);
    },

    LOAD_WEAPON_CELL: function (item, index, group) {
        if (item.type != "item_weapon") return;

        const serial = item.serial_number ? "<br>" + LANGUAGE.labels.serial + UTILS.ESCAPE_HTML(String(item.serial_number)) : "";
        const info = serial + INVENTORY.TOOLTIP.ADD_WEAPON(item);
        const weight = UTILS.GET_ITEM_WEIGHT(item.weight, item.count);
        const url = imageCache[item.name];
        const iconOpacityExtra = UTILS.ITEM_ICON_OPACITY_EXTRA(item);
        $("#secondInventoryElement").append(
            `<div data-label='${item.label}' data-group ='${group}' class='item item-filled' id='item-${index}' data-tooltip="${weight + info}">
        <span class='item-inv-icon' style='${UTILS.INVENTORY_SLOT_BACKGROUND_STYLE(url, "4.5vw", "7.7vh", iconOpacityExtra)}'></span>
        ${INVENTORY.WEAPON.GET_AMMO_ICON(item)}
        <div class='equipped-icon' style='display: ${!item.used && !item.used2 ? "none" : "block"};'></div>
    </div>`
        );
    },

    SETUP: function (items, info) {
        const S = this;
        $("#secondInventoryElement").html("").data("info", info);
        var divCount = 0;

        if (items.length > 0) {
            $.each(items, function () {
                divCount = divCount + 1;
            });

            for (const [index, item] of items.entries()) {
                count = item.count;
                const group = item.type != "item_weapon" ? !item.group ? 1 : item.group : 5;
                const limit = item.limit;
                S.LOAD_ITEM_CELL(item, index, group, count, limit);
                S.LOAD_WEAPON_CELL(item, index, group);
                S.BIND_ITEM_DATA(item, index);
            }
        }

        const minSlots = S.MIN_SLOTS;
        if (divCount < minSlots) {
            const emptySlots = minSlots - divCount;
            for (var i = 0; i < emptySlots; i++) {
                $("#secondInventoryElement").append(`<div class='item' data-group='0'></div>`);
            }
        }
    },

    ITEM_ADDED: function (item) {
        if (!item) return;
        const S = this;
        const $inv = $("#secondInventoryElement");
        const group = item.type !== "item_weapon" ? item.group || 1 : 5;
        const index = "sa_" + item.id + "_" + Date.now();

        S.LOAD_ITEM_CELL(item, index, group, item.count, item.limit);
        S.LOAD_WEAPON_CELL(item, index, group);
        S.BIND_ITEM_DATA(item, index);

        const $newEl = $inv.children("#item-" + index);

        const $firstEmpty = $inv.children(".item").filter(function () {
            return !$(this).data("item") && $(this)[0] !== $newEl[0];
        }).first();

        if ($firstEmpty.length) {
            $newEl.insertBefore($firstEmpty);
            $inv.children(".item").filter(function () {
                return !$(this).data("item");
            }).last().remove();
        }

        $newEl.draggable({
            helper: function (event) {
                return UTILS.BUILD_INVENTORY_DRAG_HELPER(this, event);
            },
            appendTo: "body",
            zIndex: 99999,
            revert: "invalid",
            distance: 8,
            start: function (event) {
                if (disabled) return false;
                altDragActive = !!(event.altKey || event.originalEvent?.altKey);
                stopTooltip = true;
                itemData = $(this).data("item");
                itemInventory = "second";
            },
            stop: function () {
                altDragActive = false;
                stopTooltip = false;
                itemData = $(this).data("item");
                itemInventory = "second";
            },
        });
    },

    ITEM_REMOVED: function (id, itemType) {
        const $inv = $("#secondInventoryElement");
        $inv.children(".item").filter(function () {
            const d = $(this).data("item");
            return d && d.id == id && d.type === itemType;
        }).remove();

        const total = $inv.children(".item").length;
        const minSlots = this.MIN_SLOTS;
        if (total < minSlots) {
            $inv.append(`<div class='item' data-group='0'></div>`);
        }
    },

    ITEM_UPDATED: function (id, count) {
        const $el = $("#secondInventoryElement .item").filter(function () {
            const d = $(this).data("item");
            return d && d.id == id;
        });
        if (!$el.length) return;
        $el.find(".count span").text(count);
        const d = $el.data("item");
        if (d) {
            d.count = count;
            $el.data("item", d);
        }
    },

    SET_TITLE: function (title) {
        const el = document.getElementById("satchelTitle");
        if (el) el.innerHTML = title;
    },

    SET_CURRENT_CAPACITY: function (cap) {
        const cur = document.getElementById("current-cap-value");
        if (cur) cur.innerHTML = cap;
        UTILS.APPLY_INV_CAPACITY_WARNING($("#secondInventoryHud .capacity"), cap, SECONDARY_CAPACITY);
    },

    SET_CAPACITY: function (cap, weight) {
        $(".capacity").show();
        const capEl = document.getElementById("capacity-value");
        if (capEl) capEl.innerHTML = weight ? weight + " " + Config.WeightMeasure : cap;

        const w = weight != null && weight !== "" && !Number.isNaN(Number(weight)) ? Number(weight) : NaN;
        const m = Number.isFinite(w) ? w : Number(cap);
        SECONDARY_CAPACITY = Number.isFinite(m) && m > 0 ? m : null;

        const curNode = document.getElementById("current-cap-value");
        const currentNum = curNode != null ? parseFloat(String(curNode.textContent || "0").trim(), 10) : 0;
        const cur = Number.isFinite(currentNum) ? currentNum : 0;
        UTILS.APPLY_INV_CAPACITY_WARNING($("#secondInventoryHud .capacity"), cur, SECONDARY_CAPACITY);
    },

    INIT: function (title, capacity, weight) {
        $("#secondInventoryHud").append(
            `<div class='controls'><div class='controls-center'><input type='text' id='secondarysearch' placeholder='${LANGUAGE.inventorysearch}'/></div></div>`
        );

        $("#secondarysearch").bind("input", function () {
            var searchFor = $("#secondarysearch").val().toLowerCase();
            $("#secondInventoryElement .item").each(function () {
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

        $("#secondInventoryHud").fadeIn(200, () => {
            this.SCHEDULE_GROUP_STRIP();
        });

        UTILS.UPDATE_HINT_VISIBILITY();
        this.SET_TITLE(title);

        if (capacity) {
            this.SET_CAPACITY(capacity, weight);
        } else {
            this.SET_CAPACITY("0");
        }
    },

    IS_CATEGORY_STRIP: function (container) {
        return !!(container && container.id === "staticCarousel" && container.closest(".secondary-item-groups"));
    },

    SET_GROUP_NAV_TITLE: function (key) {
        const el = document.getElementById("itemGroupsNavTitleSecond");
        if (!el) return;
        el.textContent = UTILS.RESOLVE_ITEM_GROUP_TITLE_TEXT(key);
    },

    SCHEDULE_GROUP_STRIP: function () {
        const container = document.getElementById("staticCarousel");
        if (!container) {
            return;
        }

        container.style.scrollBehavior = "auto";
        container.style.width = "";
        container.style.minWidth = "";
        container.style.maxWidth = "";
        container.style.flexBasis = "";
        container.scrollLeft = 0;

        requestAnimationFrame(() => INVENTORY.MAIN.CLAMP_CAT_STRIP(container));
        setTimeout(() => {
            const c = document.getElementById("staticCarousel");
            if (c) {
                c.style.scrollBehavior = "auto";
                INVENTORY.MAIN.CLAMP_CAT_STRIP(c);
            }
        }, 450);
    },

    ITEM_GROUPS_SELECTION: function (direction) {
        const strip = document.getElementById("staticCarousel");
        if (!strip) return;

        const buttons = Array.from(strip.querySelectorAll('.dropdownButton1[data-type="itemtype"]'));
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
            /* ignore */
        }
    },
};
