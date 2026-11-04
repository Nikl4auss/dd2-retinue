# How does the mod reconcile the roster with a save that disagrees with it?

Type: grilling
Status: open
Blocked by: 11

## Question

The roster is global, not per save ("What is the shape of the roster file and its validation?"), and the load-time
rules from "How does the mod notice a member leaving and returning, and when does it act?" cover the simple cases
(away but in the party → present, no restore; present but not in the party → away; returning → retry). Decide what
happens when the save contradicts the roster in ways those rules don't settle: loading an older save (or
`tools/saves.sh restore`) where an away member is present at a lower level than its backup, or where the member was
never hired; a second save slot or a new game; a party pawn whose CharacterID cache points at a different pawn; two
saves leap-frogging one backup. Which side wins per field, when the backup is overwritten or kept, what is logged, and
whether anything must be stored (e.g. a save marker or timestamps) to tell these apart.
