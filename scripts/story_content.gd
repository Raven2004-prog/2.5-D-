extends RefCounted
class_name StoryContent

## Canon-faithful authored text for Arc 1: Ash at Greyfen.
## Callers receive a deep copy so UI pagination cannot mutate shared content.

static var DIALOGUES: Dictionary = {
	"intro_earth": {
		"speaker": "Narration",
		"role": "Earth — before the blink",
		"pages": PackedStringArray([
			"Evan sat on the edge of his old bed, his cracked phone bright in one hand and every unfinished choice waiting beyond the door.",
			"From elsewhere in the house, Ruth called that the tea was ready. He meant to answer after one more minute.",
			"He blinked. The room went away."
		]),
	},
	"arrival": {
		"speaker": "Narration",
		"role": "The Ash March",
		"pages": PackedStringArray([
			"Cold rain soaked Evan's socks into black mud. A split ash tree leaned over him; bronze light burned beneath storm clouds beyond a distant wall.",
			"His phone showed 38% and no service. On Greyfen's west tower, an amber lantern kindled without flame and held a hard-edged warning in the rain.",
			"A shout reached him as sound and fear, nothing more. Then, slowly, its broad intent caught inside his mind: Move. Danger. Now."
		]),
	},
	"lysa_token": {
		"speaker": "Lysa Fen",
		"role": "Greyfen courier",
		"pages": PackedStringArray([
			"Wrong road, longshanks. Move!",
			"Take this. No, don't admire it—hide it. Blood is already a poor disguise.",
			"If the riders ask, you found nothing. Especially me."
		]),
	},
	"mara_arrest": {
		"speaker": "Princess Mara Veyre",
		"role": "Warden of Greyfen",
		"pages": PackedStringArray([
			"Strange clothes. No papers. A dead courier's seal in your hand. You understand why my guards are not feeling charitable.",
			"Your feet will be treated. You will be questioned, watched, and kept alive while your answers remain useful.",
			"Now tell me why my private field cipher crossed half the March to find you."
		]),
	},
	"catastrophe_one": {
		"speaker": "Narration",
		"role": "First failed line",
		"pages": PackedStringArray([
			"The western horn screamed. Greyfen's soldiers ran toward a threat that was not there while the water gate ground shut behind them.",
			"Fire climbed beneath the refugee granary. Mara reached the enclosure chain as the roof lifted in one bright, terrible breath.",
			"Stone took the sky. Evan's last world became weight, smoke, and the certainty that he had arrived too late."
		]),
	},
	"return_one": {
		"speaker": "Evan Hale",
		"role": "The same rain",
		"pages": PackedStringArray([
			"No—no, I was under it. I couldn't breathe. I felt—",
			"The rain was the same. My cuts were gone. The token was gone. My phone had gone backward with everything else.",
			"Lysa looked straight at me and saw a stranger. I remembered the moment she died. She did not know my name."
		]),
	},
	"brann_prediction": {
		"speaker": "Sir Brann Korr",
		"role": "Greyfen gate commander",
		"pages": PackedStringArray([
			"You named the courier, the riders, and the blood on a seal you could not have seen. That is one tidy miracle.",
			"It buys you one hearing, lad. Not trust. Make it count before the day gets untidier."
		]),
	},
	"catastrophe_two": {
		"speaker": "Narration",
		"role": "Second failed line",
		"pages": PackedStringArray([
			"Evan found the powder early. For one breath, an empty granary looked like victory.",
			"Then the false horn turned frightened soldiers toward the refugees, the water gate held fast, and a second charge broke Nessa's clinic open.",
			"Corvin kept Evan alive long enough to ask what he remembered. When Evan would not betray Mara's contact, the Laughing Saint ended the question."
		]),
	},
	"return_two": {
		"speaker": "Evan Hale",
		"role": "Three hands on the knife",
		"pages": PackedStringArray([
			"The powder was not the plot. It was one hand holding one part of the knife.",
			"False signal. Locked water gate. Charges beneath people everyone was ready to fear.",
			"Stopping one changes where the others cut. I need the whole pattern—and people who can break it without becoming pieces in mine."
		]),
	},
	"wrong_hero": {
		"speaker": "Narration",
		"role": "Third failed line",
		"pages": PackedStringArray([
			"Evan knew their routes, their courage, and the places they had died. It felt like trust. It was only memory.",
			"He changed Lysa's path, overruled Brann's retreat, and called every fear an expense the perfect plan could afford.",
			"Lysa understood before she died: Evan had known the danger and chosen it for her. He stayed for the next collapse because dying now looked easier than living with that."
		]),
	},
	"catastrophe_three": {
		"speaker": "Evan",
		"role": "The third failed line",
		"pages": PackedStringArray([
			"Lysa looks at the blocked tunnel, then at me. She understands: I knew this route was dangerous, and I chose it for her anyway.",
			"When the roof begins to fall, I could run. Instead I stay because another death feels easier than carrying what I did.",
			"That is not courage. It is the Return teaching me to call my own life equipment."
		])
	},
	"return_three": {
		"speaker": "Evan Hale",
		"role": "No one owes him yesterday",
		"pages": PackedStringArray([
			"I stayed. I chose it. That wasn't courage; it was another choice I made for everyone else.",
			"Lysa is alive. She does not owe me the trust of someone who died. None of them do.",
			"This time I tell them what I know, what I only think, and what it may cost. Then I ask."
		]),
	},
	"powder_discovery": {
		"speaker": "Evan Hale",
		"role": "Retained evidence",
		"pages": PackedStringArray([
			"Fact: powder is stored beneath the refugee granary, reached through the old drainage tunnel.",
			"Fact: Tomas has the keys, but someone is holding his husband. Inference: coercion makes him useful, not loyal.",
			"Unknown: who placed the second charge. Removing these kegs will not stop the signal or open the gate."
		]),
	},
	"signal_discovery": {
		"speaker": "Piri Korr",
		"role": "Apprentice signaler",
		"pages": PackedStringArray([
			"The western alarm is almost regulation. The third interval is short by half a beat, and the answering horn carries the old retreat cadence.",
			"That is not an error. It sends the garrison away, then tells frightened soldiers that refugees are breaking the line.",
			"Stars and cinders. Someone forged a battle out of six notes."
		]),
	},
	"gate_discovery": {
		"speaker": "Kesh Aruun",
		"role": "Daevar envoy and engineer",
		"pages": PackedStringArray([
			"The water gate is not failing. It is being held from inside by someone with the proper key.",
			"Closed, it traps the refuge quarter and divides the defenders. Opened at the wrong moment, it floods the tunnel approach.",
			"I can free the mechanism. I cannot also persuade my people that a Caldran wall has suddenly become shelter."
		]),
	},
	"nessa_contribution": {
		"speaker": "Nessa Reed",
		"role": "Border surgeon",
		"pages": PackedStringArray([
			"I will move the clinic before the alarm—not because you remember my death, but because I have seen the powder marks myself.",
			"Give me a clear route, two carts, and no soldier deciding which patient looks loyal enough to save.",
			"And Evan? Staying alive is part of the plan. I will not help you call otherwise by a prettier name."
		]),
	},
	"piri_contribution": {
		"speaker": "Piri Korr",
		"role": "Apprentice signaler",
		"pages": PackedStringArray([
			"I can challenge the false cadence from the tower and mark the true order for every post that still trusts Greyfen code.",
			"My papers may not survive the questions afterward. That risk is mine to accept, not Father's to hide.",
			"Keep the stairs clear. Once I begin, every horn in the March will know someone lied."
		]),
	},
	"brann_contribution": {
		"speaker": "Sir Brann Korr",
		"role": "Greyfen gate commander",
		"pages": PackedStringArray([
			"The withdrawal order carries a royal seal. It also sends civilians into a kill lane. I've obeyed tidier lies than this one.",
			"Not today. I hold the gate, refuse the order in public, and answer for it when there is still a Greyfen left to judge me.",
			"You keep breathing, lad. That is an order I expect you to manage."
		]),
	},
	"kesh_contribution": {
		"speaker": "Kesh Aruun",
		"role": "Daevar envoy and engineer",
		"pages": PackedStringArray([
			"I will ask the refugees to enter the same wall that confined them. Do not mistake agreement under necessity for forgiveness.",
			"Mara opens the gate herself, Caldran soldiers lower their weapons first, and my people keep their own wardens.",
			"Meet those terms and I will make shelter possible. Break them and I will say so in every language your court pretends not to understand."
		]),
	},
	"lysa_contribution": {
		"speaker": "Lysa Fen",
		"role": "Greyfen courier",
		"pages": PackedStringArray([
			"I know the buyer's tunnel, his knock, and the very tragic hat he thinks makes him invisible.",
			"I choose the upper route. Not the one your ghost-Lysa used, not the one Mara would order—the one I can leave if it turns bad.",
			"You want my trust, longshanks? Be where you promised when I come back."
		]),
	},
	"mara_disclosure": {
		"speaker": "Evan Hale",
		"role": "Impossible witness",
		"pages": PackedStringArray([
			"I remember Greyfen falling. More than once. I remember people dying who are standing outside this room.",
			"I cannot prove how. I can tell you what I saw, what changed when I interfered, and where I was wrong.",
			"I won't choose anyone's risk from a life they don't remember. Ask me everything. Then let them answer for themselves."
		]),
	},
	"ash_compact": {
		"speaker": "Princess Mara Veyre",
		"role": "Ash Witness surety",
		"pages": PackedStringArray([
			"By frontier surety, I name Evan Hale and Kesh Aruun Ash Witnesses before Greyfen's Oathstone.",
			"Their testimony travels under my protection. Evan owes truthful attendance and lawful service until the Crown Convocation judges this claim.",
			"I answer publicly for his acts. If I knowingly sponsor a lie, let my claim fail with it. This is law, magistrate—not ownership."
		]),
	},
	"tomas_surrender": {
		"speaker": "Tomas Rill",
		"role": "Quartermaster and coerced sapper",
		"pages": PackedStringArray([
			"Six kegs below the granary. Two beneath the clinic road. The figures were meant to stay smaller. I am sorry about the variance.",
			"They took my husband at dawn. Every order after that looked like the same order.",
			"Here are the keys. I will name the officers. If he is already dead, I will still name them."
		]),
	},
	"corvin_lens": {
		"speaker": "Corvin Sable",
		"role": "The Laughing Saint",
		"pages": PackedStringArray([
			"Hold still, little witness. The lens dislikes a trembling subject, and I dislike sharing the stage.",
			"Oh. That is not prophecy around your soul. Those are endings—layered like doors slammed from the other side.",
			"How many deaths are you wearing? No, don't answer. A good mystery should leave before the applause."
		]),
	},
	"tribunal": {
		"speaker": "Narration",
		"role": "Greyfen tribunal",
		"pages": PackedStringArray([
			"The tribunal recorded the living before it honored the dead: Piri's cadence, Brann's refusal, Kesh's terms, Tomas's keys, and every casualty the official order had tried to rename.",
			"Evan testified only to what he could distinguish—what he saw, what he inferred, and what he could not explain.",
			"He signed the Ash Witness record. Somewhere beyond mortal notice, stable command closed one hidden door and set another farther ahead."
		]),
	},
	"ending": {
		"speaker": "Narration",
		"role": "Bound for Lysford",
		"pages": PackedStringArray([
			"Greyfen receded behind the caravan: black walls, amber lamps, and rain brightening over the marsh.",
			"Everyone beside Evan remembered one surviving line. He carried the others—their trust, their deaths, and the harm he had done while trying to save them.",
			"Ahead waited Lysford and five claims to a broken crown. Evan was still afraid. This time, he went alive."
		]),
	},
}


static var FOLIO_ENTRIES: Dictionary = {
	"phone": {
		"title": "Cracked Phone",
		"body": "38% battery at arrival. No service and no supernatural link to Earth. It returns to the anchor state with Evan's other possessions; only his memory of later use persists.",
	},
	"token": {
		"title": "Bloodied Courier Token",
		"body": "Carries Mara's private field cipher and ties Lysa's murdered courier to Greyfen. It is physical evidence: each Return removes it from Evan's hand until Lysa gives it to him again.",
	},
	"powder": {
		"title": "Granary Powder",
		"body": "Kegs hidden beneath the refugee granary form one foundation of the false flag. Removing them alone changes the catastrophe; it does not stop the false signal or sabotaged gate.",
	},
	"false_horn": {
		"title": "Altered Horn Cadence",
		"body": "A shortened third interval conceals an old retreat command inside a western alarm. It draws the garrison away, then turns soldiers toward refugees labeled as escapees.",
	},
	"water_gate": {
		"title": "Sabotaged Water Gate",
		"body": "The mechanism is held from inside with an authorized key. Its closure divides defenders and traps Refuge Row; opening it badly can flood the tunnel approach.",
	},
	"return_rule": {
		"title": "The Return",
		"body": "Only Evan's true death triggers it. A hidden, automatic anchor moves forward in stable conditions. Body, possessions, proof, and relationships reset; imperfect memory and trauma remain.",
	},
	"soul_scar": {
		"title": "Soul Scar",
		"body": "The body returns uninjured, but pain memory, nightmares, dissociation, and damage to Evan's retained self accumulate. A useful death is still an injury, never a free resource.",
	},
	"ash_witness": {
		"title": "Ash Witness Compact",
		"body": "A public frontier surety, not a spell or claim of ownership. Evan owes truthful attendance and lawful service; Mara protects him, bears liability, and risks her royal claim if she sponsors a lie.",
	},
}


static func get_dialogue(id: String) -> Dictionary:
	var dialogue: Dictionary = DIALOGUES.get(id, {})
	return dialogue.duplicate(true)
