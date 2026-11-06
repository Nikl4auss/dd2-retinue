-- REFramework glue: the roster part of the Retinue menu (uses imgui). The decisions and texts live in
-- Retinue/roster.lua; the store (game/roster_store) does the adopting and releasing.

local roster = require("Retinue.roster")

local M = {}

-- Returns { draw = function(self, store, party, unit_label, backups) } (backups: game/backup_store, for a member's
-- level when it is not in the party and the note on a missing or damaged backup). draw runs inside Retinue.lua's
-- draw, under its pcall.
-- Pressing Adopt or Release asks for an inline confirmation; the result of a failed one stays on a line until the
-- next button press.
function M.new()
    local self = { pending = nil, last_error = nil, generation = nil }

    local function view_by_id(party, id)
        for _, view in ipairs(party.views()) do
            if roster.canonical_id(view.offline_id) == id then return view end
        end
        return nil
    end

    local function run(store, party, pending)
        local ok, err
        if pending.action == "adopt" then
            local view = view_by_id(party, pending.offline_id)
            if view then ok, err = store:adopt(view) else err = "not_in_party" end
        else
            ok, err = store:release(pending.offline_id)
        end
        if ok then
            self.last_error = nil
        else
            local verb = pending.action == "adopt" and "Adopt" or "Release"
            self.last_error = string.format("%s %s: %s", verb, pending.name, roster.error_text(err))
        end
    end

    function self:draw(store, party, unit_label, backups)
        if store.generation ~= self.generation then
            self.generation = store.generation
            self.pending, self.last_error = nil, nil
        end
        local r = store.roster
        local pending = self.pending
        imgui.text(unit_label .. " \194\183 " .. roster.state_text(r)) -- middle dot
        if store.save_failed then imgui.text("Could not save roster.json (see log)") end
        if r then
            for _, w in ipairs(r.warnings) do imgui.text(w) end
            for _, m in ipairs(r.members) do
                local view = store.found[m.offline_id]
                imgui.text(roster.member_text(m, {
                    level = (view and party.level(view)) or backups.level(m.offline_id),
                    in_party = view ~= nil,
                    ambiguous = store.ambiguous[m.offline_id] == true,
                    backup_note = backups.note(m.offline_id),
                }))
                if not pending then
                    imgui.same_line()
                    if imgui.button("Release##" .. m.offline_id) then
                        self.last_error = nil
                        self.pending = { action = "release", offline_id = m.offline_id, name = m.name }
                    end
                end
            end
        end
        for _, view in ipairs(party.views()) do
            if (view.slot == 1 or view.slot == 2) and roster.find(r, view.offline_id) == nil then
                local name = view.name or "?"
                local label = roster.pawn_text(name, party.level(view))
                local id = roster.adoptable(view)
                if id then
                    imgui.text(label)
                    if not pending then
                        imgui.same_line()
                        if imgui.button("Adopt##" .. view.slot) then
                            self.last_error = nil
                            self.pending = { action = "adopt", offline_id = id, name = name }
                        end
                    end
                else
                    imgui.text(label .. " - cannot adopt: " .. roster.error_text("no_offline_id"))
                end
            end
        end
        pending = self.pending
        if pending then
            if pending.action == "adopt" then
                imgui.text("Adopt " .. pending.name .. " into your retinue? Gear you give them is lost if they're dismissed or lost.")
            else
                imgui.text("Release " .. pending.name .. "? Their progress will be lost.")
            end
            if imgui.button("Yes##retinue_confirm") then
                self.pending = nil
                run(store, party, pending)
            end
            imgui.same_line()
            if imgui.button("No##retinue_confirm") then self.pending = nil end
        end
        if self.last_error then imgui.text(self.last_error) end
    end

    return self
end

return M
