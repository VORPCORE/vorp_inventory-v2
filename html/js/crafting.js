

let craftingRecipes = [];
let craftingExternalCounts = null;
let craftingPanelSavedPos = null;
let craftingPanelUserDragged = false;
let craftingSelectedRecipeIndex = null;

const CRAFTING = {

    ICON: {
        RESOLVE_LAYER: function (itemName) {
            const key = String(itemName);
            const url = imageCache[key];
            const layer = String(url);
            return layer.replace(/;+\s*$/, "");
        },

        IMG_SRC: function (itemName) {
            const layer = CRAFTING.ICON.RESOLVE_LAYER(itemName);
            const m = /url\(\s*["']?([^"')]+)["']?\s*\)/.exec(layer);
            return m ? m[1] : "img/items/placeholder.png";
        },
    },

    COUNTS: {
        NORMALIZE_MAP: function (m) {
            const o = {};
            if (!m || typeof m !== "object") return o;
            for (const k of Object.keys(m)) {
                o[String(k)] = Number(m[k]) || 0;
            }
            return o;
        },

        MAIN_STANDARD_STACKS_BY_NAME: function () {
            const counts = {};

            if (typeof mainInventoryItemsCache !== "object" || !mainInventoryItemsCache) {
                return counts;
            }

            for (const key of Object.keys(mainInventoryItemsCache)) {
                const item = mainInventoryItemsCache[key];
                if (item.type !== "item_standard") continue;

                const name = String(item.name);
                if (!name) continue;

                counts[name] = (counts[name] || 0) + (Number(item.count) || 0);
            }

            return counts;
        },

        GET_MERGED_INVENTORY: function () {
            const cache = CRAFTING.COUNTS.NORMALIZE_MAP(CRAFTING.COUNTS.MAIN_STANDARD_STACKS_BY_NAME());
            const ext = craftingExternalCounts;
            if (!ext || typeof ext !== "object")
                return cache;

            const out = Object.assign({}, cache);
            const en = CRAFTING.COUNTS.NORMALIZE_MAP(ext);

            for (const k of Object.keys(en)) {
                out[k] = en[k];
            }
            return out;
        },
    },

    RECIPE: {
        FIRST_REWARD_ENTRY: function (reward) {
            const keys = Object.keys(reward).sort();

            if (!keys.length) return { key: null, amount: 0 };
            const key = keys[0];
            return { key, amount: Number(reward[key]) || 0 };
        },
    },

    PANEL: {
        PLACE_BESIDE_INVENTORY: function () {
            const $panel = $("#handCraftingPanel");
            if (!$panel.length || !$panel.is(":visible")) return;

            const margin = 12;
            const dockGap = 12;
            const topOffset = 34;
            const main = document.getElementById("inventoryElement");
            const second = document.getElementById("secondInventoryElement");
            const hud = document.getElementById("inventoryHud");
            let left;
            let top;

            if (main) {
                const mainRect = main.getBoundingClientRect();
                const secondRect = second ? second.getBoundingClientRect() : null;
                const secondVisible = second && $("#secondInventoryElement").is(":visible") && secondRect && secondRect.width > 0 && secondRect.height > 0;
                const pw = $panel.outerWidth() || Math.round(window.innerWidth * 0.22) || 220;
                const ph = $panel.outerHeight() || 200;

                if (mainRect.width > 2 && mainRect.height > 2) {
                    if (secondVisible) {
                        const gapCenter = (mainRect.right + secondRect.left) / 2;
                        left = gapCenter - pw / 2;
                    } else {
                        left = mainRect.right + dockGap;
                    }
                    top = mainRect.top + (mainRect.height - ph) / 2 - topOffset;
                }
            }

            if ((left == null || top == null) && hud) {
                const st = window.getComputedStyle(hud);

                if (st.display !== "none" && st.visibility !== "hidden") {
                    const r = hud.getBoundingClientRect();

                    if (r.width > 2 && r.height > 2) {
                        const pw = $panel.outerWidth() || Math.round(window.innerWidth * 0.22) || 220;
                        left = r.right + dockGap;
                        top = Math.max(margin, r.top);

                        if (left + pw > window.innerWidth - margin) {
                            left = Math.max(margin, r.left - pw - dockGap);
                        }
                    }
                }
            }

            if (left == null || top == null) {
                const pw = $panel.outerWidth() || Math.round(window.innerWidth * 0.22) || 220;
                left = Math.max(margin, window.innerWidth - margin - pw);
                top = window.innerHeight * 0.12;
            }

            $panel.css({
                position: "fixed",
                left: Math.round(left),
                top: Math.round(top),
                zIndex: 12000,
            });
        },

        CLAMP_TO_WINDOW: function () {
            const $panel = $("#handCraftingPanel");
            if (!$panel.length || !$panel.is(":visible")) return;

            let left = parseFloat($panel.css("left"));
            let top = parseFloat($panel.css("top"));
            if (!Number.isFinite(left)) left = 0;
            if (!Number.isFinite(top)) top = 0;

            const w = $panel.outerWidth() || 220;
            const h = $panel.outerHeight() || 200;
            const maxL = Math.max(0, window.innerWidth - w);
            const maxT = Math.max(0, window.innerHeight - h);

            left = Math.min(Math.max(0, left), maxL);
            top = Math.min(Math.max(0, top), maxT);
            left = Math.round(left);
            top = Math.round(top);
            $panel.css({ left, top });

            if (craftingPanelUserDragged) {
                craftingPanelSavedPos = { left, top };
            }
        },

        INIT_DRAGGABLE: function () {
            const $panel = $("#handCraftingPanel");
            if (!$panel.length || !$.fn.draggable) return;

            if ($panel.data("ui-draggable")) return;

            $panel.draggable({
                handle: ".hand-crafting-panel-title",
                containment: "window",
                scroll: false,
                stop: function () {
                    const $p = $(this);
                    craftingPanelUserDragged = true;
                    craftingPanelSavedPos = {
                        left: Math.round(parseFloat($p.css("left")) || 0),
                        top: Math.round(parseFloat($p.css("top")) || 0),
                    };
                },
            });
        },
    },

    RECIPE_LIST: {
        CLOSE: function () {
            $(document).off("click.handCraftDd keydown.handCraftDd");
            $(window).off("resize.handCraftDd");
            $("#handCraftingPanel .hand-crafting-panel-inner").off("scroll.handCraftDd");
            $("#handCraftingRecipeList").off("wheel.handCraftDd mouseenter.handCraftTip mouseleave.handCraftTip");
            $(document).off("mousemove.handCraftTip");
            $(".tooltip").remove();
        },

        BIND_TOOLTIPS: function () {
            const $items = $("#handCraftingRecipeList .hand-crafting-panel-recipe-item[data-index]");
            $items.off("mouseenter.handCraftTip mouseleave.handCraftTip");

            $items.on("mouseenter.handCraftTip", function (e) {
                if (typeof stopTooltip !== "undefined" && stopTooltip) return;

                $(".tooltip").remove();
                $(document).off("mousemove.handCraftTip");

                const $el = $(this);
                const idx = Number($el.attr("data-index"));
                const recipe = craftingRecipes[idx];
                if (!recipe) return;

                const label = recipe.label != null ? String(recipe.label).trim() : "";
                if (!label) return;

                const $tooltip = $("<div/>")
                    .addClass("tooltip tooltip--rich tooltip--rich-compact-hud")
                    .css("pointer-events", "none")
                    .appendTo("body");

                INVENTORY.TOOLTIP.APPEND_HUD_STRIP($tooltip, label, null);
                INVENTORY.TOOLTIP.APPLY_LOCATION($tooltip, $el, e);

                $(document).on("mousemove.handCraftTip", function (moveEv) {
                    INVENTORY.TOOLTIP.STATIC_ITEMS($tooltip, moveEv);
                });
            });

            $items.on("mouseleave.handCraftTip", function () {
                $(document).off("mousemove.handCraftTip");
                $(".tooltip").remove();
            });
        },

        BIND_SCROLL: function () {
            $("#handCraftingRecipeList")
                .off("wheel.handCraftDd")
                .on("wheel.handCraftDd", function (e) {
                    const ev = e.originalEvent || e;
                    e.preventDefault();
                    this.scrollLeft += ev.deltaY || ev.deltaX || 0;
                });
        },

        SYNC_SELECTION_UI: function () {
            const $list = $("#handCraftingRecipeList");
            if (!$list.length) return;

            $list.children(".hand-crafting-panel-recipe-item").removeClass("is-selected");
            const idx = craftingSelectedRecipeIndex;
            if (idx == null || !Number.isFinite(idx) || !craftingRecipes[idx]) return;

            $list.children('[data-index="' + String(idx) + '"]').addClass("is-selected");
        },

        REBUILD: function () {
            CRAFTING.RECIPE_LIST.CLOSE();
            if (craftingSelectedRecipeIndex != null && (!Number.isFinite(craftingSelectedRecipeIndex) || !craftingRecipes[craftingSelectedRecipeIndex])) {
                craftingSelectedRecipeIndex = null;
            }

            const $list = $("#handCraftingRecipeList");
            if (!$list.length) return;
            $list.empty();

            if (!craftingRecipes.length) {
                const emptyLab = (LANGUAGE && LANGUAGE.handcraftingNoRecipes) || "No recipes";
                $list.append(
                    $("<li/>", {
                        class: "hand-crafting-panel-recipe-item hand-crafting-panel-recipe-item-empty",
                        role: "presentation",
                    }).text(emptyLab)
                );
                CRAFTING.RECIPE_LIST.BIND_SCROLL();
                CRAFTING.RENDER_SELECTION();
                return;
            }

            for (let i = 0; i < craftingRecipes.length; i++) {
                const r = craftingRecipes[i];
                const fr = CRAFTING.RECIPE.FIRST_REWARD_ENTRY(r.reward);
                const imgSrc = CRAFTING.ICON.IMG_SRC(fr.key);
                const $img = $("<img/>", { src: imgSrc, alt: "" });

                $img.on("error", function () {
                    $(this).off("error").attr("src", CRAFTING.ICON.IMG_SRC(""));
                });

                const $li = $("<li/>", {
                    class: "hand-crafting-panel-recipe-item",
                    role: "option",
                    "data-index": String(i),
                });

                $li.append($("<span/>", { class: "hand-crafting-panel-recipe-thumb" }).append($img));
                $li.on("click", function () {
                    craftingSelectedRecipeIndex = Number($(this).attr("data-index"));
                    CRAFTING.RECIPE_LIST.SYNC_SELECTION_UI();
                    CRAFTING.RENDER_SELECTION();
                });

                $list.append($li);
            }
            CRAFTING.RECIPE_LIST.SYNC_SELECTION_UI();
            CRAFTING.RECIPE_LIST.BIND_SCROLL();
            CRAFTING.RECIPE_LIST.BIND_TOOLTIPS();
        },
    },

    SET_RECIPES: function (list) {
        craftingRecipes = Array.isArray(list) ? list : [];
        CRAFTING.RECIPE_LIST.REBUILD();
        CRAFTING.RENDER_SELECTION();
    },

    RENDER_SELECTION: function () {
        const idx = craftingSelectedRecipeIndex;
        const recipe = idx != null && Number.isFinite(idx) && craftingRecipes[idx] != null ? craftingRecipes[idx] : null;
        const $img = $("#handCraftingRewardImg");
        const $desc = $("#handCraftingDesc");
        const $needed = $("#handCraftingNeeded");
        const $prompt = $("#handCraftingSelectPrompt");
        const $preview = $("#handCraftingPanel .hand-crafting-panel-preview");
        const $neededTitle = $("#handCraftingPanel .hand-crafting-panel-needed-title");
        const $craftBtn = $("#handCraftingCraftBtn");
        $needed.empty();

        if (!recipe) {
            $img.attr("src", CRAFTING.ICON.IMG_SRC(""));
            $desc.text("");
            $prompt.show();
            $preview.hide();
            $neededTitle.hide();
            $needed.hide();
            $craftBtn.hide();
            CRAFTING.UPDATE_CRAFT_BUTTON();
            return;
        }

        $prompt.hide();
        $preview.show();
        $neededTitle.show();
        $needed.show();
        $craftBtn.show();

        const firstReward = CRAFTING.RECIPE.FIRST_REWARD_ENTRY(recipe.reward);
        $img.attr("src", CRAFTING.ICON.IMG_SRC(firstReward.key));
        $img.off("error.handCraft").on("error.handCraft", function () {
            $(this).off("error.handCraft").attr("src", CRAFTING.ICON.IMG_SRC(""));
        });

        $desc.text((recipe.desc != null && String(recipe.desc)) || "");

        const needed = recipe.needed;
        const keys = Object.keys(needed).sort();
        const counts = CRAFTING.COUNTS.GET_MERGED_INVENTORY();

        for (let i = 0; i < keys.length; i++) {
            const name = keys[i];
            const need = Number(needed[name]) || 0;
            const have = counts[String(name)] || 0;
            const ok = have >= need;
            const iconLayer = CRAFTING.ICON.RESOLVE_LAYER(name);
            const iconStyle = UTILS.INVENTORY_SLOT_BACKGROUND_STYLE(iconLayer, "3.1vw", "5.35vh", "");
            const $row = $("<div/>", { class: "craft-req" + (ok ? "" : " craft-req--missing") });
            const $slot = $("<div/>", { class: "craft-req__slot" });
            $slot.append($("<span/>", { class: "item-inv-icon" }).attr("style", iconStyle));
            $row.append($slot);
            $row.append(
                $("<span/>", { class: "craft-req__count" }).text(
                    String(have) + " / " + String(need)
                )
            );
            $needed.append($row);
        }

        CRAFTING.UPDATE_CRAFT_BUTTON();
    },

    SELECTED_RECIPE_INDEX: function () {
        const idx = craftingSelectedRecipeIndex;
        if (idx == null || !Number.isFinite(idx)) return null;
        if (!craftingRecipes[idx]) return null;

        return idx;
    },

    HAS_MATERIALS_FOR_RECIPE: function (item) {

        const counts = CRAFTING.COUNTS.GET_MERGED_INVENTORY();

        for (const name of Object.keys(item.needed)) {
            const need = Number(item.needed[name]) || 0;
            const have = counts[String(name)] || 0;
            if (have < need) return false;
        }
        return true;
    },

    UPDATE_CRAFT_BUTTON: function () {
        const $btn = $("#handCraftingCraftBtn");
        if (!$btn.length) return;

        const idx = CRAFTING.SELECTED_RECIPE_INDEX();
        const recipe = idx != null ? craftingRecipes[idx] : null;
        $btn.prop("disabled", !(recipe && CRAFTING.HAS_MATERIALS_FOR_RECIPE(recipe)));
    },

    EXECUTE: function () {
        if (!Config.EnableHandCraftButton) return;
        const idx = CRAFTING.SELECTED_RECIPE_INDEX();
        if (idx == null) return;

        const recipe = craftingRecipes[idx];
        if (!recipe || !CRAFTING.HAS_MATERIALS_FOR_RECIPE(recipe))
            return;

        $.post(`https://${GetParentResourceName()}/handCraftingExecute`,
            JSON.stringify({ recipeIndex: idx })
        );
    },

    REFRESH_REQUIREMENTS: function () {
        CRAFTING.RENDER_SELECTION();
    },

    REQUEST_RECIPES: function () {
        $.post(`https://${GetParentResourceName()}/requestHandCraftingRecipes`, JSON.stringify({})).fail(function () {
            CRAFTING.SET_RECIPES([]);
        });
    },

    OPEN: function () {
        if (!Config.EnableHandCraftButton) return;
        if (type !== "main") return;

        const $panel = $("#handCraftingPanel");
        const $btn = $("#handCraftingOpenBtn");
        $panel.css("display", "block").attr("aria-hidden", "false");
        $btn.attr("aria-expanded", "true");

        requestAnimationFrame(function () {
            if (craftingPanelUserDragged && craftingPanelSavedPos) {
                $panel.css({
                    position: "fixed",
                    left: craftingPanelSavedPos.left,
                    top: craftingPanelSavedPos.top,
                    zIndex: 12000,
                });
            } else {
                CRAFTING.PANEL.PLACE_BESIDE_INVENTORY();
            }
            CRAFTING.PANEL.CLAMP_TO_WINDOW();
            CRAFTING.PANEL.INIT_DRAGGABLE();
        });

        CRAFTING.REQUEST_RECIPES();

        if (!craftingRecipes.length) {
            CRAFTING.RENDER_SELECTION();
        } else {
            CRAFTING.REFRESH_REQUIREMENTS();
        }
    },

    CLOSE: function () {
        CRAFTING.RECIPE_LIST.CLOSE();
        craftingSelectedRecipeIndex = null;

        $("#handCraftingPanel").hide().attr("aria-hidden", "true");
        $("#handCraftingOpenBtn").attr("aria-expanded", "false");
    },

    TOGGLE_FROM_UI: function (event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }
        if (!Config.EnableHandCraftButton) return;
        if ($("#handCraftingOpenBtn").prop("disabled")) return;

        if (type !== "main") return;

        const $p = $("#handCraftingPanel");
        if ($p.is(":visible")) {
            CRAFTING.CLOSE();
        } else {
            CRAFTING.OPEN();
        }
    },

};

window.addEventListener("message", function (event) {
    const data = event.data;
    if (!data.action) return;

    if (data.action === "handCraftingRecipes") {
        if (!Config.EnableHandCraftButton) return;
        CRAFTING.SET_RECIPES(data.recipes);
        return;
    }

    if (data.action === "handCraftingInventoryCounts") {
        craftingExternalCounts = data.counts || {};
        if (Config.EnableHandCraftButton && $("#handCraftingPanel").is(":visible")) {
            CRAFTING.REFRESH_REQUIREMENTS();
        }
    }
});

$(document).ready(function () {
    $("#handCraftingOpenBtn").on("click", CRAFTING.TOGGLE_FROM_UI);


    $("#handCraftingCloseBtn").on("click", function () {
        CRAFTING.CLOSE();
    });

    $("#handCraftingCraftBtn").on("click", function () {
        CRAFTING.EXECUTE();
    });

    $(window).on("resize", function () {
        CRAFTING.PANEL.CLAMP_TO_WINDOW();
    });
});
