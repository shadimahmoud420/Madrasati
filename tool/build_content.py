"""Builds the content bundled with the app:

  assets/content/catalog.json        every grade (1–12) and its subjects
  assets/content/packs/<grade>.json  demo lessons, books, questions, exams
  assets/content/images/*.png        question images (needs Pillow)

Run: python3 tool/build_content.py

The lessons below are DEMO content written for testing the app. They follow
the Palestinian curriculum topics but are not the official Ministry text;
replace them with approved content from the admin side (see
docs/CONTENT_GUIDE.md). Bump PACK_VERSION whenever a bundled pack changes so
installed apps re-import it.
"""
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "content")
PACK_VERSION = 1

# ---------------------------------------------------------------- catalog

SUBJECTS = {
    "arabic": ("اللغة العربية", "menu_book", 0xFF0F766E),
    "math": ("الرياضيات", "calculate", 0xFF2563EB),
    "science": ("العلوم والحياة", "science", 0xFF16A34A),
    "islamic": ("التربية الإسلامية", "mosque", 0xFF0D9488),
    "english": ("اللغة الإنجليزية", "translate", 0xFF7C3AED),
    "national": ("التنشئة الوطنية والحياتية", "flag", 0xFFDC2626),
    "social": ("الدراسات الاجتماعية", "public", 0xFFB45309),
    "tech": ("التكنولوجيا", "computer", 0xFF475569),
    "physics": ("الفيزياء", "bolt", 0xFFEA580C),
    "chemistry": ("الكيمياء", "biotech", 0xFF0891B2),
    "biology": ("الأحياء", "eco", 0xFF15803D),
    "geography": ("الجغرافيا", "map", 0xFFA16207),
    "history": ("التاريخ", "history_edu", 0xFF9F1239),
}

ORDINALS = ["الأول", "الثاني", "الثالث", "الرابع", "الخامس", "السادس", "السابع", "الثامن", "التاسع", "العاشر",
            "الحادي عشر", "الثاني عشر"]

LOWER = ["arabic", "math", "science", "islamic", "english", "national"]
UPPER = ["arabic", "math", "science", "islamic", "english", "social", "tech"]
SCI = ["arabic", "english", "islamic", "math", "physics", "chemistry", "biology", "tech"]
LIT = ["arabic", "english", "islamic", "math", "geography", "history", "tech"]


def grade(gid, number, stage, keys, stream=None):
    name = f"الصف {ORDINALS[number - 1]}"
    return {
        "id": gid,
        "number": number,
        "stage": stage,
        "stream": stream,
        "name": name,
        "subjects": [
            {"id": f"{gid}_{k}", "key": k, "name": SUBJECTS[k][0], "icon": SUBJECTS[k][1], "color": SUBJECTS[k][2]}
            for k in keys
        ],
    }


def catalog(bundled):
    grades = []
    for n in range(1, 5):
        grades.append(grade(f"g{n}", n, "lowerBasic", LOWER))
    for n in range(5, 11):
        grades.append(grade(f"g{n}", n, "upperBasic", UPPER))
    for n in (11, 12):
        grades.append(grade(f"g{n}_sci", n, "secondary", SCI, "علمي"))
        grades.append(grade(f"g{n}_lit", n, "secondary", LIT, "أدبي"))
    return {
        "stages": [
            {"id": "lowerBasic", "name": "المرحلة الأساسية الدنيا", "hint": "من الصف الأول إلى الرابع"},
            {"id": "upperBasic", "name": "المرحلة الأساسية العليا", "hint": "من الصف الخامس إلى العاشر"},
            {"id": "secondary", "name": "المرحلة الثانوية", "hint": "الحادي عشر والثاني عشر (التوجيهي)"},
        ],
        "grades": grades,
        "bundledPacks": bundled,
    }


# ---------------------------------------------------------------- questions

def q(kind, d, prompt, **kw):
    item = {"type": kind, "difficulty": d, "prompt": prompt}
    item.update({k: v for k, v in kw.items() if v is not None})
    return item


def mcq(d, prompt, options, answer, why, image=None):
    return q("mcq", d, prompt, options=options, answer=answer, explanation=why, image=image)


def tf(d, prompt, answer, why):
    return q("trueFalse", d, prompt, answer=answer, explanation=why)


def fill(d, prompt, accepted, why):
    return q("fill", d, prompt, accepted=accepted, explanation=why)


def short(d, prompt, accepted, why):
    return q("short", d, prompt, accepted=accepted, explanation=why)


def num(d, prompt, answer, why, tolerance=0.001, unit=None):
    return q("numeric", d, prompt, answer=answer, tolerance=tolerance, unit=unit, explanation=why)


def match(d, prompt, pairs, why):
    return q("match", d, prompt, pairs=pairs, explanation=why)


def essay(d, prompt, model):
    return q("essay", d, prompt, modelAnswer=model)


# ---------------------------------------------------------------- lessons

def lesson(lid, title, objectives, explanation, examples, key_points, summary, questions, video=None):
    for i, item in enumerate(questions, 1):
        item["id"] = f"{lid}_q{i}"
    return {
        "id": lid,
        "title": title,
        "objectives": objectives,
        "explanation": explanation,
        "examples": examples,
        "keyPoints": key_points,
        "summary": summary,
        "videoUrl": video,
        "questions": questions,
    }


G4_MATH = [
    {
        "id": "g4_math_u1", "semester": 1, "title": "الوحدة الأولى: الكسور",
        "lessons": [
            lesson(
                "g4_math_l1", "مفهوم الكسر",
                ["أتعرّف معنى الكسر.", "أميّز البسط والمقام.", "أكتب كسرًا يعبّر عن شكل مقسّم إلى أجزاء متساوية."],
                "الكسر هو جزء من كل مقسوم إلى أجزاء متساوية. نكتب الكسر بعددين بينهما خط:\n"
                "• العدد في الأعلى يسمى البسط، ويدل على عدد الأجزاء التي أخذناها.\n"
                "• العدد في الأسفل يسمى المقام، ويدل على عدد الأجزاء المتساوية التي قُسِّم إليها الكل.\n"
                "مثلًا إذا قسمنا رغيفًا إلى 4 أجزاء متساوية وأكلنا جزءًا واحدًا، نكون قد أكلنا 1/4 (ربع) الرغيف.\n"
                "شرط مهم: يجب أن تكون الأجزاء متساوية حتى نستطيع التعبير عنها بكسر.",
                [
                    "قُسِّمت بيتزا إلى 8 قطع متساوية، أكل أحمد 3 قطع. الكسر الذي أكله: 3/8، البسط 3 والمقام 8.",
                    "في صف 5 تلاميذ، 2 منهم بنات. كسر البنات = 2/5.",
                ],
                ["البسط: عدد الأجزاء المأخوذة.", "المقام: عدد الأجزاء المتساوية الكلي.",
                 "النصف = 1/2، الربع = 1/4، الثلث = 1/3.", "الأجزاء يجب أن تكون متساوية."],
                "الكسر يمثل جزءًا من كل مقسوم لأجزاء متساوية، ويُكتب على صورة بسط/مقام.",
                [
                    mcq(1, "في الكسر 3/5، ما هو البسط؟", ["5", "3", "8", "2"], 1, "البسط هو العدد الموجود فوق خط الكسر وهو 3."),
                    tf(1, "المقام هو العدد الموجود أسفل خط الكسر.", True, "المقام يكتب أسفل الخط ويدل على عدد الأجزاء الكلي."),
                    fill(1, "في الكسر 2/7 يسمى العدد 7 ________.", ["المقام", "مقام"], "العدد أسفل الخط هو المقام."),
                    mcq(2, "ما الكسر الذي يمثله الجزء الملوّن في الشكل؟", ["1/4", "3/4", "4/3", "1/3"], 1,
                        "الدائرة مقسمة إلى 4 أجزاء متساوية، لُوّن منها 3، فالكسر 3/4.", image="images/fraction_3_4.png"),
                    num(2, "قُسِّمت كعكة إلى 8 أجزاء متساوية وأُكل منها 3 أجزاء. كم جزءًا بقي؟", 5,
                        "عدد الأجزاء الباقية = 8 − 3 = 5."),
                    match(2, "صِل كل كسر باسمه:", [["1/2", "نصف"], ["1/4", "ربع"], ["1/3", "ثلث"]],
                          "1/2 نصف، 1/4 ربع، 1/3 ثلث."),
                    short(3, "اكتب الكسر الذي يعبّر عن جزأين من خمسة أجزاء متساوية.", ["2/5"],
                          "عدد الأجزاء المأخوذة 2 (البسط) من أصل 5 (المقام): 2/5."),
                    tf(3, "إذا قسمنا تفاحة إلى جزأين غير متساويين فإن كل جزء يساوي 1/2.", False,
                       "لا يكون الجزء نصفًا إلا إذا كان الجزآن متساويين."),
                    essay(3, "اشرح بكلماتك لماذا يجب أن تكون الأجزاء متساوية عند كتابة كسر.",
                          "لأن الكسر يقارن الجزء بالكل، فإذا كانت الأجزاء مختلفة في الحجم لا يدل العدد نفسه على الكمية نفسها، "
                          "فلا يمكن أن نقول إن كل جزء يساوي ربعًا مثلًا."),
                ],
            ),
            lesson(
                "g4_math_l2", "مقارنة الكسور",
                ["أقارن بين كسرين لهما المقام نفسه.", "أقارن بين كسرين لهما البسط نفسه."],
                "لمقارنة كسرين نستخدم القواعد التالية:\n"
                "1) إذا تساوى المقامان: الكسر الأكبر هو صاحب البسط الأكبر، مثل 5/7 > 3/7.\n"
                "2) إذا تساوى البسطان: الكسر الأكبر هو صاحب المقام الأصغر، مثل 1/3 > 1/5، "
                "لأن تقسيم الشيء إلى 3 أجزاء يعطي أجزاء أكبر من تقسيمه إلى 5 أجزاء.\n"
                "نستخدم الرموز: > أكبر من، < أصغر من، = يساوي.",
                ["قارن بين 2/9 و 7/9: المقامان متساويان و 7 > 2، إذن 7/9 > 2/9.",
                 "قارن بين 3/4 و 3/8: البسطان متساويان والمقام 4 أصغر من 8، إذن 3/4 > 3/8."],
                ["المقامات متساوية ← نقارن البسوط.", "البسوط متساوية ← المقام الأصغر يعني كسرًا أكبر."],
                "عند تساوي المقامات نقارن البسوط، وعند تساوي البسوط فالمقام الأصغر يعطي الكسر الأكبر.",
                [
                    mcq(1, "أيّ الكسرين أكبر: 4/9 أم 7/9؟", ["4/9", "7/9", "متساويان"], 1, "المقامان متساويان، و7 أكبر من 4."),
                    tf(1, "1/2 أكبر من 1/4.", True, "البسطان متساويان والمقام 2 أصغر من 4، فالنصف أكبر."),
                    mcq(2, "اختر الرمز المناسب: 3/5 ___ 3/8", [">", "<", "="], 0, "المقام 5 أصغر من 8، إذن 3/5 > 3/8."),
                    fill(2, "إذا تساوت مقامات الكسور فإن الكسر الأكبر هو صاحب ________ الأكبر.", ["البسط", "بسط"],
                         "عند تساوي المقامات نقارن البسوط."),
                    mcq(3, "رتّب الكسور من الأصغر إلى الأكبر: 1/3، 1/6، 1/2",
                        ["1/2، 1/3، 1/6", "1/6، 1/3، 1/2", "1/3، 1/6، 1/2"], 1,
                        "البسوط متساوية، فالمقام الأكبر يعني الكسر الأصغر: 1/6 < 1/3 < 1/2."),
                    tf(3, "أكلت سارة 2/8 من فطيرة وأكلت ليلى 2/4 من فطيرة مماثلة، إذن أكلت سارة أكثر.", False,
                       "2/4 أكبر من 2/8 لأن المقام 4 أصغر، إذن ليلى أكلت أكثر."),
                    short(4, "اكتب كسرًا مقامه 10 ويكون أكبر من 7/10 وأصغر من 9/10.", ["8/10", "4/5"],
                          "الكسر الوحيد بمقام 10 بينهما هو 8/10."),
                ],
            ),
        ],
    },
    {
        "id": "g4_math_u2", "semester": 2, "title": "الوحدة الثانية: القياس",
        "lessons": [
            lesson(
                "g4_math_l3", "محيط المستطيل والمربع",
                ["أتعرّف مفهوم المحيط.", "أحسب محيط المستطيل والمربع."],
                "المحيط هو طول الخط الذي يحيط بالشكل، أي مجموع أطوال أضلاعه.\n"
                "• محيط المستطيل = (الطول + العرض) × 2.\n"
                "• محيط المربع = طول الضلع × 4، لأن أضلاعه الأربعة متساوية.\n"
                "يقاس المحيط بوحدات الطول مثل السنتيمتر (سم) والمتر (م).",
                ["مستطيل طوله 6 سم وعرضه 4 سم: المحيط = (6 + 4) × 2 = 20 سم.",
                 "مربع طول ضلعه 5 م: المحيط = 5 × 4 = 20 م."],
                ["المحيط = مجموع أطوال الأضلاع.", "محيط المستطيل = (الطول + العرض) × 2.", "محيط المربع = الضلع × 4."],
                "نحسب المحيط بجمع أطوال الأضلاع، وللمستطيل (الطول + العرض) × 2 وللمربع الضلع × 4.",
                [
                    num(1, "مربع طول ضلعه 3 سم. ما محيطه؟", 12, "المحيط = 3 × 4 = 12 سم.", unit="سم"),
                    num(2, "مستطيل طوله 7 سم وعرضه 3 سم. ما محيطه؟", 20, "المحيط = (7 + 3) × 2 = 20 سم.", unit="سم"),
                    tf(1, "يقاس المحيط بوحدة السنتيمتر المربع.", False, "المحيط طول، فيقاس بالسنتيمتر وليس بالسنتيمتر المربع."),
                    mcq(2, "أيّ القوانين التالية يحسب محيط المستطيل؟",
                        ["الطول × العرض", "(الطول + العرض) × 2", "الطول + العرض", "الضلع × 4"], 1,
                        "نجمع الطول والعرض ثم نضرب في 2."),
                    num(3, "حديقة مربعة الشكل محيطها 36 مترًا. ما طول ضلعها؟", 9, "طول الضلع = 36 ÷ 4 = 9 م.", unit="م"),
                    num(4, "مستطيل محيطه 30 سم وطوله 10 سم. ما عرضه؟", 5,
                        "نصف المحيط = 15 = الطول + العرض، إذن العرض = 15 − 10 = 5 سم.", unit="سم"),
                ],
            ),
        ],
    },
]

G4_SCIENCE = [
    {
        "id": "g4_science_u1", "semester": 1, "title": "الوحدة الأولى: النبات",
        "lessons": [
            lesson(
                "g4_science_l1", "أجزاء النبات ووظائفها",
                ["أسمّي أجزاء النبات الرئيسية.", "أذكر وظيفة كل جزء."],
                "يتكون النبات الزهري من أجزاء رئيسية لكل منها وظيفة:\n"
                "• الجذر: يثبّت النبات في التربة ويمتص الماء والأملاح منها.\n"
                "• الساق: تحمل الأوراق والأزهار، وتنقل الماء من الجذر إلى باقي النبات.\n"
                "• الأوراق: تصنع الغذاء للنبات بوجود ضوء الشمس، وتسمى هذه العملية البناء الضوئي.\n"
                "• الزهرة: مسؤولة عن التكاثر، ومنها تتكون الثمار والبذور.",
                ["عندما نسقي شجرة الليمون يمتص جذرها الماء، ثم تنقله الساق إلى الأوراق.",
                 "زهرة شجرة البرتقال تتحول إلى ثمرة برتقال بداخلها بذور."],
                ["الجذر: تثبيت وامتصاص.", "الساق: حمل ونقل.", "الورقة: صنع الغذاء.", "الزهرة: التكاثر."],
                "أجزاء النبات أربعة رئيسية: الجذر والساق والأوراق والزهرة، ولكل منها وظيفة تحافظ على حياة النبات.",
                [
                    mcq(1, "ما الجزء الذي يمتص الماء من التربة؟", ["الورقة", "الزهرة", "الجذر", "الثمرة"], 2,
                        "الجذر يمتص الماء والأملاح من التربة."),
                    tf(1, "الأوراق هي الجزء الذي يصنع الغذاء للنبات.", True, "تصنع الأوراق الغذاء بعملية البناء الضوئي."),
                    match(2, "صِل كل جزء بوظيفته:",
                          [["الجذر", "يثبّت النبات"], ["الساق", "تنقل الماء"], ["الزهرة", "التكاثر"]],
                          "الجذر للتثبيت، الساق للنقل، الزهرة للتكاثر."),
                    fill(2, "تسمى عملية صنع الغذاء في الأوراق بعملية البناء ________.", ["الضوئي", "ضوئي"],
                         "البناء الضوئي يحتاج ضوء الشمس."),
                    mcq(3, "إذا قُطعت ساق نبتة صغيرة من منتصفها، فماذا يحدث للأوراق العليا غالبًا؟",
                        ["تنمو أسرع", "تذبل لأن الماء لا يصلها", "تتحول إلى أزهار"], 1,
                        "الساق تنقل الماء، فإذا قطعت لا يصل الماء للأوراق فتذبل."),
                    essay(3, "لماذا لا تستطيع النبتة العيش طويلًا بلا جذور؟",
                          "لأن الجذور تثبتها في التربة وتمتص الماء والأملاح، وبدونها لا يصل الماء إلى الساق والأوراق فتذبل وتموت."),
                ],
            ),
            lesson(
                "g4_science_l2", "حاجات النبات",
                ["أذكر ما يحتاجه النبات لينمو.", "أصمم تجربة بسيطة تبيّن أهمية الضوء."],
                "يحتاج النبات إلى عدة أشياء لينمو بشكل سليم:\n"
                "• الماء: يمتصه من التربة عبر الجذور.\n"
                "• ضوء الشمس: تستخدمه الأوراق لصنع الغذاء.\n"
                "• الهواء: يأخذ منه ثاني أكسيد الكربون لصنع الغذاء.\n"
                "• التربة: يثبت فيها ويحصل منها على الأملاح المعدنية.\n"
                "تجربة: ضع نبتتين متشابهتين، واحدة في الضوء وأخرى في خزانة مظلمة، واسقهما بالماء نفسه. "
                "بعد أسبوع تصفرّ النبتة المظلمة وتضعف.",
                ["النبتة الموضوعة قرب النافذة تميل نحو الضوء.", "نبتة لم تُسقَ أسبوعين تذبل أوراقها."],
                ["الماء والضوء والهواء والتربة حاجات أساسية.", "الضوء ضروري لصنع الغذاء."],
                "ينمو النبات عند توفر الماء والضوء والهواء والتربة، وغياب أحدها يضعف النبات.",
                [
                    mcq(1, "أيّ مما يلي ليس من حاجات النبات الأساسية؟", ["الماء", "الضوء", "الصوت", "الهواء"], 2,
                        "الصوت ليس من الحاجات الأساسية للنبات."),
                    tf(1, "تستطيع النباتات الخضراء صنع غذائها في الظلام الدامس.", False, "تحتاج الأوراق إلى الضوء لصنع الغذاء."),
                    fill(2, "يأخذ النبات من الهواء غاز ثاني أكسيد ________.", ["الكربون", "كربون"],
                         "يستخدم النبات ثاني أكسيد الكربون في صنع الغذاء."),
                    mcq(2, "وُضعت نبتة في خزانة مظلمة أسبوعًا. ماذا تتوقع؟",
                        ["تصبح أكثر خضرة", "تصفرّ وتضعف", "لا تتغير أبدًا"], 1, "غياب الضوء يمنع صنع الغذاء فتضعف."),
                    essay(3, "صف تجربة تبيّن أن النبات يحتاج إلى الماء.",
                          "نأخذ نبتتين متشابهتين في الظروف نفسها من ضوء وهواء، نسقي الأولى ولا نسقي الثانية، "
                          "وبعد أيام نلاحظ أن النبتة التي لم تُسقَ ذبلت، فنستنتج أن الماء ضروري."),
                ],
            ),
        ],
    },
]

G4_ARABIC = [
    {
        "id": "g4_arabic_u1", "semester": 1, "title": "الوحدة الأولى: قواعد اللغة",
        "lessons": [
            lesson(
                "g4_arabic_l1", "الجملة الاسمية والجملة الفعلية",
                ["أميّز الجملة الاسمية من الجملة الفعلية.", "أكوّن جملًا اسمية وفعلية."],
                "تنقسم الجملة في اللغة العربية إلى نوعين:\n"
                "• الجملة الاسمية: هي التي تبدأ باسم، وتتكون من مبتدأ وخبر. مثل: «الشمسُ مشرقةٌ».\n"
                "• الجملة الفعلية: هي التي تبدأ بفعل، وتتكون من فعل وفاعل. مثل: «ذهبَ الطالبُ إلى المدرسة».\n"
                "لمعرفة نوع الجملة ننظر إلى أول كلمة فيها: إن كانت اسمًا فهي اسمية، وإن كانت فعلًا فهي فعلية.",
                ["«غزةُ جميلةٌ»: تبدأ باسم (غزة) فهي جملة اسمية.",
                 "«يقرأُ أحمدُ القصةَ»: تبدأ بفعل (يقرأ) فهي جملة فعلية."],
                ["الجملة الاسمية تبدأ باسم: مبتدأ + خبر.", "الجملة الفعلية تبدأ بفعل: فعل + فاعل.",
                 "ننظر إلى الكلمة الأولى لتحديد النوع."],
                "الجملة الاسمية تبدأ باسم والجملة الفعلية تبدأ بفعل.",
                [
                    mcq(1, "ما نوع جملة: «البحرُ واسعٌ»؟", ["جملة اسمية", "جملة فعلية"], 0, "تبدأ باسم (البحر)."),
                    mcq(1, "ما نوع جملة: «لعبَ الأطفالُ في الحديقة»؟", ["جملة اسمية", "جملة فعلية"], 1, "تبدأ بفعل (لعب)."),
                    tf(1, "تتكون الجملة الاسمية من فعل وفاعل.", False, "الجملة الاسمية تتكون من مبتدأ وخبر."),
                    fill(2, "تتكون الجملة الاسمية من مبتدأ و________.", ["خبر", "الخبر"], "ركنا الجملة الاسمية: المبتدأ والخبر."),
                    match(2, "صِل كل جملة بنوعها:",
                          [["المعلمُ نشيطٌ", "اسمية"], ["كتبَ الطالبُ الدرسَ", "فعلية"]],
                          "الأولى تبدأ باسم والثانية تبدأ بفعل."),
                    short(3, "حوّل الجملة «يزرعُ الفلاحُ الزيتونَ» إلى جملة اسمية.",
                          ["الفلاح يزرع الزيتون", "الفلاحُ يزرعُ الزيتونَ"],
                          "نبدأ بالاسم: الفلاحُ يزرعُ الزيتونَ."),
                ],
            ),
        ],
    },
]

G9_MATH = [
    {
        "id": "g9_math_u1", "semester": 1, "title": "الوحدة الأولى: المعادلات",
        "lessons": [
            lesson(
                "g9_math_l1", "حل المعادلات الخطية بمتغير واحد",
                ["أحل معادلة خطية بمتغير واحد.", "أتحقق من صحة الحل بالتعويض."],
                "المعادلة الخطية بمتغير واحد على الصورة: أ س + ب = جـ، حيث أ ≠ 0.\n"
                "لحلها نعزل المتغير س في طرف واحد باستخدام العمليات العكسية، مع إجراء العملية نفسها على الطرفين:\n"
                "1) نطرح (أو نجمع) الحد الثابت من الطرفين.\n"
                "2) نقسم الطرفين على معامل س.\n"
                "3) نتحقق بتعويض قيمة س في المعادلة الأصلية.",
                ["حل المعادلة 2س + 3 = 11: نطرح 3 ← 2س = 8، نقسم على 2 ← س = 4. التحقق: 2(4) + 3 = 11 ✓",
                 "حل المعادلة 5س − 7 = 3س + 9: ننقل الحدود ← 2س = 16 ← س = 8."],
                ["ما نفعله في طرف نفعله في الطرف الآخر.", "نستخدم العمليات العكسية لعزل المتغير.", "نتحقق دائمًا بالتعويض."],
                "نحل المعادلة الخطية بعزل المتغير باستخدام العمليات العكسية على الطرفين ثم نتحقق بالتعويض.",
                [
                    num(1, "حل المعادلة: س + 7 = 12. ما قيمة س؟", 5, "س = 12 − 7 = 5."),
                    num(1, "حل المعادلة: 3س = 21. ما قيمة س؟", 7, "س = 21 ÷ 3 = 7."),
                    num(2, "حل المعادلة: 2س + 3 = 11. ما قيمة س؟", 4, "2س = 8 ← س = 4."),
                    mcq(2, "ما الخطوة الأولى المناسبة لحل 4س − 5 = 15؟",
                        ["قسمة الطرفين على 4", "جمع 5 إلى الطرفين", "طرح 15 من الطرفين"], 1,
                        "نتخلص من الحد الثابت أولًا بجمع 5: 4س = 20."),
                    tf(2, "س = 3 حل للمعادلة 5س − 4 = 11.", True, "5(3) − 4 = 15 − 4 = 11 ✓"),
                    num(3, "حل المعادلة: 5س − 7 = 3س + 9. ما قيمة س؟", 8, "2س = 16 ← س = 8."),
                    num(4, "عمر أحمد الآن س سنة، وبعد 6 سنوات يصبح عمره ضعف عمره قبل سنة واحدة. ما قيمة س؟", 8,
                        "س + 6 = 2(س − 1) ← س + 6 = 2س − 2 ← س = 8."),
                    essay(3, "اشرح لماذا يجب إجراء العملية نفسها على طرفي المعادلة.",
                          "لأن المعادلة تمثل توازنًا بين طرفين متساويين، وإجراء العملية نفسها على الطرفين يحافظ على التساوي."),
                ],
            ),
        ],
    },
    {
        "id": "g9_math_u2", "semester": 2, "title": "الوحدة الثانية: الهندسة",
        "lessons": [
            lesson(
                "g9_math_l2", "نظرية فيثاغورس",
                ["أتعرّف نظرية فيثاغورس.", "أحسب طول ضلع مجهول في مثلث قائم الزاوية."],
                "في المثلث القائم الزاوية يسمى الضلع المقابل للزاوية القائمة «الوتر»، وهو أطول الأضلاع.\n"
                "تنص نظرية فيثاغورس على أن: مربع طول الوتر = مجموع مربعي طولي الضلعين الآخرين.\n"
                "أي: جـ² = أ² + ب²، حيث جـ الوتر.\n"
                "ويمكن استخدام عكس النظرية لمعرفة هل المثلث قائم الزاوية أم لا.",
                ["مثلث قائم ضلعاه 3 سم و 4 سم: جـ² = 9 + 16 = 25 ← جـ = 5 سم.",
                 "مثلث قائم وتره 13 وأحد ضلعيه 5: ب² = 169 − 25 = 144 ← ب = 12."],
                ["الوتر يقابل الزاوية القائمة وهو الأطول.", "جـ² = أ² + ب².", "الأعداد 3، 4، 5 ثلاثية فيثاغورسية."],
                "في المثلث القائم: مربع الوتر يساوي مجموع مربعي الضلعين الآخرين.",
                [
                    tf(1, "الوتر هو أطول أضلاع المثلث القائم الزاوية.", True, "الوتر يقابل الزاوية القائمة وهي أكبر زاوية."),
                    num(2, "مثلث قائم الزاوية طولا ضلعيه 6 سم و 8 سم. ما طول الوتر؟", 10,
                        "جـ² = 36 + 64 = 100 ← جـ = 10 سم.", unit="سم"),
                    num(2, "مثلث قائم الزاوية وتره 13 سم وأحد ضلعيه 5 سم. ما طول الضلع الآخر؟", 12,
                        "ب² = 169 − 25 = 144 ← ب = 12 سم.", unit="سم"),
                    mcq(2, "في المثلث القائم المرسوم: الضلع الرأسي 3 وحدات والقاعدة 4 وحدات (كل علامة زرقاء تفصل وحدة). ما طول الوتر الملوّن بالأحمر؟", ["7", "5", "12", "25"], 1,
                        "جـ² = 3² + 4² = 25 ← جـ = 5.", image="images/right_triangle.png"),
                    mcq(3, "أيّ الثلاثيات التالية يمكن أن تكون أطوال أضلاع مثلث قائم؟",
                        ["4، 5، 6", "5، 12، 13", "2، 3، 4", "6، 7، 9"], 1, "25 + 144 = 169 = 13²."),
                    num(4, "سلّم طوله 10 أمتار يستند إلى جدار، وبُعد أسفله عن الجدار 6 أمتار. على أي ارتفاع يلامس الجدار؟", 8,
                        "الارتفاع² = 100 − 36 = 64 ← الارتفاع = 8 م.", unit="م"),
                ],
            ),
        ],
    },
]

G9_SCIENCE = [
    {
        "id": "g9_science_u1", "semester": 1, "title": "الوحدة الأولى: القوة والحركة",
        "lessons": [
            lesson(
                "g9_science_l1", "قانون نيوتن الأول (القصور الذاتي)",
                ["أنص على قانون نيوتن الأول.", "أفسّر مواقف حياتية باستخدام مفهوم القصور الذاتي."],
                "ينص قانون نيوتن الأول على أن: الجسم الساكن يبقى ساكنًا، والجسم المتحرك يبقى متحركًا بسرعة ثابتة "
                "وفي خط مستقيم، ما لم تؤثر فيه قوة محصلة تغيّر حالته.\n"
                "تسمى ممانعة الجسم لتغيير حالته الحركية «القصور الذاتي»، ويزداد القصور الذاتي بزيادة كتلة الجسم.\n"
                "لذلك يندفع الركاب إلى الأمام عند توقف الحافلة فجأة، ولهذا نستخدم حزام الأمان.",
                ["عند توقف السيارة فجأة يندفع جسم الراكب إلى الأمام لأنه يميل إلى الاستمرار في حركته.",
                 "سحب مفرش الطاولة بسرعة يبقي الأطباق في مكانها تقريبًا بسبب قصورها الذاتي."],
                ["لا يغيّر الجسم حالته الحركية إلا بقوة محصلة.", "القصور الذاتي يزداد بزيادة الكتلة.",
                 "حزام الأمان تطبيق على القانون الأول."],
                "يحافظ الجسم على حالته من سكون أو حركة منتظمة ما لم تؤثر فيه قوة محصلة، وهذا هو القصور الذاتي.",
                [
                    tf(1, "الجسم الساكن يبقى ساكنًا ما لم تؤثر فيه قوة محصلة.", True, "هذا نص قانون نيوتن الأول."),
                    mcq(1, "يسمى ميل الجسم إلى مقاومة التغير في حالته الحركية:",
                        ["التسارع", "القصور الذاتي", "الوزن", "الاحتكاك"], 1, "هذا تعريف القصور الذاتي."),
                    mcq(2, "لماذا يندفع الركاب إلى الأمام عند توقف الحافلة فجأة؟",
                        ["بسبب قوة تدفعهم للأمام", "لأن أجسامهم تميل للاستمرار في الحركة", "بسبب الجاذبية"], 1,
                        "بسبب القصور الذاتي تستمر أجسامهم في الحركة."),
                    mcq(2, "أيّ الجسمين قصوره الذاتي أكبر؟", ["دراجة هوائية", "شاحنة محمّلة"], 1,
                        "الشاحنة كتلتها أكبر فقصورها الذاتي أكبر."),
                    fill(3, "يزداد القصور الذاتي للجسم بزيادة ________.", ["كتلته", "الكتلة", "كتلة"],
                         "القصور الذاتي مرتبط بالكتلة."),
                    essay(3, "فسّر أهمية حزام الأمان في السيارة اعتمادًا على قانون نيوتن الأول.",
                          "عند التوقف المفاجئ يستمر جسم الراكب في الحركة للأمام بسبب القصور الذاتي، "
                          "فيؤثر حزام الأمان بقوة توقفه وتمنعه من الاصطدام بالزجاج أو المقعد الأمامي."),
                ],
            ),
            lesson(
                "g9_science_l2", "قانون نيوتن الثاني",
                ["أنص على قانون نيوتن الثاني.", "أحسب القوة والكتلة والتسارع باستخدام العلاقة ق = ك × ت."],
                "ينص قانون نيوتن الثاني على أن: تسارع الجسم يتناسب طرديًا مع القوة المحصلة المؤثرة فيه، "
                "وعكسيًا مع كتلته، ويكون في اتجاه القوة المحصلة.\n"
                "الصيغة الرياضية: ق = ك × ت\n"
                "• ق: القوة المحصلة وتقاس بالنيوتن (N).\n"
                "• ك: الكتلة وتقاس بالكيلوغرام (kg).\n"
                "• ت: التسارع ويقاس بالمتر لكل ثانية مربعة (m/s²).\n"
                "النيوتن الواحد هو القوة التي تكسب جسمًا كتلته 1 kg تسارعًا مقداره 1 m/s².",
                ["جسم كتلته 2 kg يتسارع بمقدار 3 m/s²: ق = 2 × 3 = 6 N.",
                 "قوة محصلة 20 N تؤثر في جسم كتلته 5 kg: ت = 20 ÷ 5 = 4 m/s²."],
                ["ق = ك × ت.", "زيادة القوة تزيد التسارع.", "زيادة الكتلة تقلل التسارع (للقوة نفسها).",
                 "وحدة القوة: النيوتن N = kg·m/s²."],
                "التسارع يزداد بزيادة القوة المحصلة ويقل بزيادة الكتلة، والعلاقة ق = ك × ت.",
                [
                    num(1, "جسم كتلته 2 kg يتحرك بتسارع 3 m/s². ما مقدار القوة المحصلة المؤثرة فيه بالنيوتن؟", 6,
                        "ق = ك × ت = 2 × 3 = 6 N.", unit="N"),
                    mcq(1, "ما وحدة قياس القوة؟", ["الجول", "النيوتن", "الواط", "الكيلوغرام"], 1, "تقاس القوة بالنيوتن."),
                    num(2, "قوة محصلة مقدارها 20 N تؤثر في جسم كتلته 5 kg. ما تسارعه؟", 4,
                        "ت = ق ÷ ك = 20 ÷ 5 = 4 m/s².", unit="m/s²"),
                    tf(2, "إذا ضاعفنا كتلة الجسم مع بقاء القوة ثابتة فإن تسارعه يتضاعف.", False,
                       "التسارع يتناسب عكسيًا مع الكتلة، فيقل إلى النصف."),
                    match(2, "صِل كل كمية بوحدة قياسها:", [["القوة", "N"], ["الكتلة", "kg"], ["التسارع", "m/s²"]],
                          "القوة بالنيوتن، والكتلة بالكيلوغرام، والتسارع بـ m/s²."),
                    num(3, "ما كتلة جسم تكسبه قوة محصلة مقدارها 12 N تسارعًا قدره 4 m/s²؟", 3,
                        "ك = ق ÷ ت = 12 ÷ 4 = 3 kg.", unit="kg"),
                    num(4, "دُفعت عربة كتلتها 10 kg بقوة 50 N، وكانت قوة الاحتكاك 20 N. ما تسارع العربة؟", 3,
                        "القوة المحصلة = 50 − 20 = 30 N، ت = 30 ÷ 10 = 3 m/s².", unit="m/s²"),
                ],
            ),
        ],
    },
]

G9_ENGLISH = [
    {
        "id": "g9_english_u1", "semester": 1, "title": "Unit 1: Grammar",
        "lessons": [
            lesson(
                "g9_english_l1", "The Present Perfect",
                ["أستخدم زمن المضارع التام للتعبير عن تجارب وأحداث لها أثر في الحاضر.",
                 "أكوّن جملًا مثبتة ومنفية وأسئلة بالمضارع التام."],
                "يتكون زمن المضارع التام (Present Perfect) من: have / has + التصريف الثالث للفعل (past participle).\n"
                "• نستخدم has مع he / she / it، و have مع I / you / we / they.\n"
                "• نستخدمه للحديث عن تجارب في الحياة دون تحديد الوقت: I have visited Jerusalem.\n"
                "• ولأحداث بدأت في الماضي وما زالت مستمرة مع for و since: She has lived in Gaza since 2010.\n"
                "• النفي: have not (haven't) / has not (hasn't). السؤال: Have you finished?",
                ["I have finished my homework. (أنهيت واجبي)", "He has not seen the film yet.",
                 "Have you ever been to Jericho?"],
                ["have/has + V3.", "for + مدة، since + نقطة بداية.", "ever / never / already / yet كلمات دالة."],
                "Present Perfect = have/has + V3، ويعبر عن تجارب أو أحداث ماضية مرتبطة بالحاضر.",
                [
                    mcq(1, "She ___ finished her project.", ["have", "has", "is", "did"], 1, "مع she نستخدم has."),
                    mcq(1, "Choose the past participle of «write».", ["wrote", "writed", "written", "writing"], 2,
                        "write – wrote – written."),
                    fill(2, "They have lived here ___ 2015. (for / since)", ["since"], "since مع نقطة بداية محددة."),
                    fill(2, "I have studied English ___ six years. (for / since)", ["for"], "for مع مدة زمنية."),
                    tf(2, "«He have eaten breakfast» is a correct sentence.", False, "الصحيح: He has eaten breakfast."),
                    short(3, "Make it negative: «We have seen this film.»",
                          ["We have not seen this film.", "We haven't seen this film.", "We have not seen this film",
                           "We haven't seen this film"], "نضيف not بعد have."),
                    essay(3, "Write two sentences about things you have done this year.",
                          "Example: I have read three books this year. I have helped my brother with his homework."),
                ],
            ),
        ],
    },
]


def book(subject_id, title, units):
    """Paginates the subject's lessons into readable book pages."""
    pages = [{"number": 1, "text": f"{title}\n\nالمحتويات:\n" +
              "\n".join(f"• {u['title']}" for u in units), "lessonId": None}]
    for unit in units:
        pages.append({"number": len(pages) + 1, "text": unit["title"], "lessonId": None})
        for les in unit["lessons"]:
            les["bookPage"] = len(pages) + 1
            body = f"{les['title']}\n\n{les['explanation']}"
            pages.append({"number": len(pages) + 1, "text": body, "lessonId": les["id"]})
            extra = "أمثلة محلولة:\n" + "\n".join(f"• {e}" for e in les["examples"]) + \
                    "\n\nأتذكّر:\n" + "\n".join(f"• {k}" for k in les["keyPoints"])
            pages.append({"number": len(pages) + 1, "text": extra, "lessonId": les["id"]})
    return {"id": f"{subject_id}_book", "title": title, "pdfUrl": None, "pages": pages}


def subject(subject_id, title, units, exams):
    for unit in units:
        for les in unit["lessons"]:
            les["unitId"] = unit["id"]
    return {"id": subject_id, "books": [book(subject_id, title, units)], "units": units, "exams": exams}


def pack(grade_id, subjects):
    return {"gradeId": grade_id, "version": PACK_VERSION, "demo": True, "subjects": subjects}


PACKS = {
    "g4": pack("g4", [
        subject("g4_math", "كتاب الرياضيات – الصف الرابع (نسخة تجريبية)", G4_MATH, [
            {"id": "g4_math_exam1", "title": "امتحان تجريبي – الرياضيات", "durationMinutes": 20, "questionCount": 10},
        ]),
        subject("g4_science", "كتاب العلوم والحياة – الصف الرابع (نسخة تجريبية)", G4_SCIENCE, [
            {"id": "g4_science_exam1", "title": "امتحان تجريبي – العلوم", "durationMinutes": 15, "questionCount": 8},
        ]),
        subject("g4_arabic", "كتاب اللغة العربية – الصف الرابع (نسخة تجريبية)", G4_ARABIC, []),
    ]),
    "g9": pack("g9", [
        subject("g9_math", "كتاب الرياضيات – الصف التاسع (نسخة تجريبية)", G9_MATH, [
            {"id": "g9_math_exam1", "title": "امتحان تجريبي – الرياضيات", "durationMinutes": 30, "questionCount": 10},
        ]),
        subject("g9_science", "كتاب العلوم – الصف التاسع (نسخة تجريبية)", G9_SCIENCE, [
            {"id": "g9_science_exam1", "title": "امتحان تجريبي – العلوم", "durationMinutes": 25, "questionCount": 10},
        ]),
        subject("g9_english", "English – Grade 9 (Demo)", G9_ENGLISH, []),
    ]),
}


# ---------------------------------------------------------------- images

def make_images():
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("Pillow not installed; keeping existing images")
        return
    s = 4
    size = 400 * s
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    box = (40 * s, 40 * s, 360 * s, 360 * s)
    d.ellipse(box, fill=(229, 231, 235, 255))
    d.pieslice(box, -90, 180, fill=(37, 99, 235, 255))
    c = size // 2
    for end in [(c, 40 * s), (360 * s, c), (c, 360 * s), (40 * s, c)]:
        d.line([(c, c), end], fill=(17, 24, 39, 255), width=6 * s)
    d.ellipse(box, outline=(17, 24, 39, 255), width=6 * s)
    img.resize((400, 400), Image.LANCZOS).save(os.path.join(OUT, "images", "fraction_3_4.png"))

    w, h = 480 * s, 360 * s
    img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    a, b, cc = (60 * s, 300 * s), (380 * s, 300 * s), (60 * s, 60 * s)
    d.polygon([a, b, cc], fill=(219, 234, 254, 255), outline=(17, 24, 39, 255), width=6 * s)
    d.rectangle((60 * s, 270 * s, 90 * s, 300 * s), outline=(17, 24, 39, 255), width=4 * s)
    # Side labels as tick marks: 3 ticks on the vertical side, 4 on the base,
    # so the image stays language-neutral (numbers are in the prompt options).
    for i in range(1, 3):
        y = 60 * s + i * 80 * s
        d.line([(45 * s, y), (75 * s, y)], fill=(37, 99, 235, 255), width=5 * s)
    for i in range(1, 4):
        x = 60 * s + i * 80 * s
        d.line([(x, 285 * s), (x, 315 * s)], fill=(37, 99, 235, 255), width=5 * s)
    d.line([cc, b], fill=(220, 38, 38, 255), width=10 * s)
    img.resize((480, 360), Image.LANCZOS).save(os.path.join(OUT, "images", "right_triangle.png"))


def sql(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, list):
        return "array[" + ",".join(sql(x) for x in v) + "]::text[]" if v else "'{}'::text[]"
    return "'" + str(v).replace("'", "''") + "'"


def jsonb(v):
    return "null" if v is None else sql(json.dumps(v, ensure_ascii=False)) + "::jsonb"


def write_seed(cat):
    """supabase/seed.sql: the same catalog and demo content as rows, so the
    server starts in sync with the app (publish with select publish_pack(...))."""
    out = ["-- Generated by tool/build_content.py. Do not edit by hand.", "begin;"]
    for g in cat["grades"]:
        out.append(f"insert into grades (id, number, stage, stream, name) values "
                   f"({sql(g['id'])}, {g['number']}, {sql(g['stage'])}, {sql(g['stream'])}, {sql(g['name'])}) "
                   "on conflict (id) do nothing;")
        for i, s in enumerate(g["subjects"]):
            out.append(f"insert into subjects (id, grade_id, key, name, icon, color, sort) values "
                       f"({sql(s['id'])}, {sql(g['id'])}, {sql(s['key'])}, {sql(s['name'])}, {sql(s['icon'])}, "
                       f"{s['color']}, {i}) on conflict (id) do nothing;")
    for gid, data in PACKS.items():
        for subj in data["subjects"]:
            for b in subj["books"]:
                out.append(f"insert into books (id, subject_id, title, pdf_url) values "
                           f"({sql(b['id'])}, {sql(subj['id'])}, {sql(b['title'])}, null) on conflict (id) do nothing;")
            for ui, u in enumerate(subj["units"]):
                out.append(f"insert into units (id, subject_id, semester, title, sort) values "
                           f"({sql(u['id'])}, {sql(subj['id'])}, {u['semester']}, {sql(u['title'])}, {ui}) "
                           "on conflict (id) do nothing;")
                for li, l in enumerate(u["lessons"]):
                    out.append(
                        "insert into lessons (id, unit_id, title, objectives, explanation, examples, key_points, "
                        "summary, video_url, book_page, sort, published) values "
                        f"({sql(l['id'])}, {sql(u['id'])}, {sql(l['title'])}, {sql(l['objectives'])}, "
                        f"{sql(l['explanation'])}, {sql(l['examples'])}, {sql(l['keyPoints'])}, {sql(l['summary'])}, "
                        f"{sql(l['videoUrl'])}, {sql(l['bookPage'])}, {li}, true) on conflict (id) do nothing;")
                    for qi, q in enumerate(l["questions"]):
                        out.append(
                            "insert into questions (id, lesson_id, type, difficulty, prompt, options, answer, accepted, "
                            "pairs, tolerance, unit, explanation, model_answer, image, sort) values "
                            f"({sql(q['id'])}, {sql(l['id'])}, {sql(q['type'])}, {q['difficulty']}, {sql(q['prompt'])}, "
                            f"{sql(q.get('options')) if q.get('options') else 'null'}, {jsonb(q.get('answer'))}, "
                            f"{sql(q.get('accepted')) if q.get('accepted') else 'null'}, {jsonb(q.get('pairs'))}, "
                            f"{sql(q.get('tolerance'))}, {sql(q.get('unit'))}, {sql(q.get('explanation'))}, "
                            f"{sql(q.get('modelAnswer'))}, {sql(q.get('image'))}, {qi}) on conflict (id) do nothing;")
            for b in subj["books"]:
                for pg in b["pages"]:
                    out.append(f"insert into book_pages (book_id, number, text, lesson_id) values "
                               f"({sql(b['id'])}, {pg['number']}, {sql(pg['text'])}, {sql(pg['lessonId'])}) "
                               "on conflict do nothing;")
            for e in subj["exams"]:
                out.append(f"insert into exams (id, subject_id, title, duration_minutes, question_count) values "
                           f"({sql(e['id'])}, {sql(subj['id'])}, {sql(e['title'])}, {e['durationMinutes']}, "
                           f"{e['questionCount']}) on conflict (id) do nothing;")
    out.append("commit;")
    path = os.path.join(ROOT, "supabase", "seed.sql")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def main():
    os.makedirs(os.path.join(OUT, "packs"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "images"), exist_ok=True)
    for gid, data in PACKS.items():
        with open(os.path.join(OUT, "packs", f"{gid}.json"), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
    cat = catalog({gid: PACK_VERSION for gid in PACKS})
    with open(os.path.join(OUT, "catalog.json"), "w", encoding="utf-8") as f:
        json.dump(cat, f, ensure_ascii=False, indent=1)
    write_seed(cat)
    make_images()
    print("Wrote catalog + packs:", ", ".join(PACKS))


if __name__ == "__main__":
    main()
