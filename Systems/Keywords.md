**Deploy**
Trigger the ability upon placing the card on the board. ^deploy

**Banish**
Removes a card from the game. Does not trigger [[Keywords#^lastword|Last Word]]. ^banish

**Devour**
Target an allied unit, [[Keywords#^destroy|destroy]] it, then boost self by it’s power. ^devour

**Hoard $X$**
Trigger the ability if you have **$X$** or more sellary. ^hoard

**Destroy**
Reduce health to 0. ^destroy

**Last Word**
Trigger the ability upon the [[Keywords#^destroy|destruction]] of the card. ^lastword

**Tribute $X$**
Upon playing a card, you may pay **$X$** sellary to trigger the ability. ^trib

**Upkeep $X$**
Deduct **$X$** sellary. If this condition is not met, the ability is not triggered. ^upk

**Income $X$**  
[[Keywords#^prof|Profit X]] at the start of your turn. ^inc

**Profit $X$**  
Gain **$X$** sellary. ^prof

**Timer $X$**
At the end of your turn, reduce timer by 1. Once the timer reaches 0, trigger the ability. ^time

**Counter** $X$
A numerical value. ^count

**Control**
To control a card means to have it placed on your side of the board. ^control

**Crit**
Deal double damage instead.  ^be2a13

**Spy**
Place the card on opponent’s board. ^spy

**Charge $X$** 
^charge

**Pay $X$**
Spend **$X$** sellary to trigger the abiliity. ^pay

**Order**
Use 1 charge to triger an ability ^order

**Boost $X$**
Increase unit’s power by $X$. ^boost

**Heal $X$**
Increase unit’s power by $X$, but can’t go over base health. ^boost

**Spot Valid 67**
If you see the number 6 adjacent to number 7, trigger the ability. ^67

**Deathblow**
Trigger the ability upon destroying a unit. ^deathblow
# Keyword linker
```bash
cd "/run/media/vsht/External SS/Citadel/Personal/TLLCG — Think Look Like Card Game/"

find . -type f -name '*.md' -exec sh -c '
  for f do
    grep -q "TLLCG" "$f" || continue
    sed -Ei \
      -e "s/\bDeploy\b/[[Keywords#^deploy|Deploy]]/g" \
      -e "s/\bdeploy\b/[[Keywords#^deploy|deploy]]/g" \
      -e "s/\bBanish\b/[[Keywords#^banish|Banish]]/g" \
      -e "s/\bbanish\b/[[Keywords#^banish|banish]]/g" \
      -e "s/\bDevour\b/[[Keywords#^devour|Devour]]/g" \
      -e "s/\bdevour\b/[[Keywords#^devour|devour]]/g" \
      -e "s/\bHoard\b/[[Keywords#^hoard|Hoard]]/g" \
      -e "s/\bhoard\b/[[Keywords#^hoard|hoard]]/g" \
      -e "s/\bDestroy\b/[[Keywords#^destroy|Destroy]]/g" \
      -e "s/\bdestroy\b/[[Keywords#^destroy|destroy]]/g" \
      -e "s/\bLast Word\b/[[Keywords#^lastword|Last Word]]/g" \
      -e "s/\blast word\b/[[Keywords#^lastword|last word]]/g" \
      -e "s/\bTribute\b/[[Keywords#^trib|Tribute]]/g" \
      -e "s/\btribute\b/[[Keywords#^trib|tribute]]/g" \
      -e "s/\bUpkeep\b/[[Keywords#^upk|Upkeep]]/g" \
      -e "s/\bupkeep\b/[[Keywords#^upk|upkeep]]/g" \
      -e "s/\bIncome\b/[[Keywords#^inc|Income]]/g" \
      -e "s/\bincome\b/[[Keywords#^inc|income]]/g" \
      -e "s/\bProfit\b/[[Keywords#^prof|Profit]]/g" \
      -e "s/\bprofit\b/[[Keywords#^prof|profit]]/g" \
      -e "s/\bTimer\b/[[Keywords#^time|Timer]]/g" \
      -e "s/\btimer\b/[[Keywords#^time|timer]]/g" \
      -e "s/\bCounter\b/[[Keywords#^count|Counter]]/g" \
      -e "s/\bcounter\b/[[Keywords#^count|counter]]/g" \
      -e "s/\bControl\b/[[Keywords#^control|Control]]/g" \
      -e "s/\bcontrol\b/[[Keywords#^control|control]]/g" \
      -e "s/\bCrit\b/[[Keywords#^be2a13|Crit]]/g" \
      -e "s/\bcrit\b/[[Keywords#^be2a13|crit]]/g" \
      -e "s/\bSpy\b/[[Keywords#^spy|Spy]]/g" \
      -e "s/\bspy\b/[[Keywords#^spy|spy]]/g" \
      -e "s/\bCharge\b/[[Keywords#^charge|Charge]]/g" \
      -e "s/\bcharge\b/[[Keywords#^charge|charge]]/g" \
      -e "s/\bPay\b/[[Keywords#^pay|Pay]]/g" \
      -e "s/\bpay\b/[[Keywords#^pay|pay]]/g" \
      -e "s/\bOrder\b/[[Keywords#^order|Order]]/g" \
      -e "s/\border\b/[[Keywords#^order|order]]/g" \
      -e "s/\bBoost\b/[[Keywords#^boost|Boost]]/g" \
      -e "s/\bboost\b/[[Keywords#^boost|boost]]/g" \
      "$f"
  done
' sh {} +

```