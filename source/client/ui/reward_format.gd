class_name RewardFormat
## Formats a reward descriptor — {type, name, amount}, as resolved server-side by
## RedeemCodes.describe_grants — into a one-line display string. Shared by the
## redeem popup and the mail inbox so the two never drift.
## See docs/redeem_codes.md and docs/mailbox.md.


## One reward descriptor → a display line ("+100 Gold", "Health Potion ×3",
## "Title: Ember Founder", "Cosmetic: Royal Knight").
static func describe(reward: Dictionary) -> String:
	var reward_name: String = str(reward.get("name", "Reward"))
	var amount: int = int(reward.get("amount", 1))
	match str(reward.get("type", "")):
		"currency", "xp":
			return "+%d %s" % [amount, reward_name]
		"item":
			return "%s ×%d" % [reward_name, amount] if amount > 1 else reward_name
		"title":
			return "Title: %s" % reward_name
		"skin":
			return "Cosmetic: %s" % reward_name
		_:
			return reward_name
