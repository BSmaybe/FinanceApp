import Foundation

struct Quote {
    let textEn: String
    let textRu: String
    let textKk: String
    let source: String   // author/character name — kept as-is (proper names)
    let category: String // "anime", "game", "movie"

    var localizedText: String {
        let lang: String
        if let codes = UserDefaults.standard.stringArray(forKey: "AppleLanguages"),
           let first = codes.first {
            lang = String(first.prefix(2))
        } else {
            lang = String(Locale.current.language.languageCode?.identifier.prefix(2) ?? "en")
        }
        switch lang {
        case "ru": return textRu
        case "kk": return textKk
        default:   return textEn
        }
    }
}

enum DailyQuoteStore {
    static let quotes: [Quote] = [
        // ── Anime ──────────────────────────────────────────────────────────────
        Quote(
            textEn: "Hard work is worthless for those that don't believe in themselves.",
            textRu: "Упорный труд ничего не стоит для тех, кто не верит в себя.",
            textKk: "Өзіне сенбейтін адам үшін қиын еңбектің мәні жоқ.",
            source: "Naruto — Naruto Uzumaki",
            category: "anime"
        ),
        Quote(
            textEn: "If you don't take risks, you can't create a future.",
            textRu: "Если не рискуешь — не сможешь создать своё будущее.",
            textKk: "Тәуекел етпесең, болашағыңды жасай алмайсың.",
            source: "One Piece — Monkey D. Luffy",
            category: "anime"
        ),
        Quote(
            textEn: "A lesson without pain is meaningless. You cannot gain something without sacrificing something else.",
            textRu: "Урок без боли бессмысленен. Невозможно что-то получить, ничем не пожертвовав.",
            textKk: "Азапсыз сабақ мағынасыз. Ештеңені бермей, ештеңе ала алмайсың.",
            source: "Fullmetal Alchemist — Edward Elric",
            category: "anime"
        ),
        Quote(
            textEn: "Equivalent exchange: to gain something you must sacrifice something of equal value.",
            textRu: "Равноценный обмен: чтобы получить, нужно пожертвовать равным.",
            textKk: "Теңдей алмасу: бірдеңе алу үшін тең нәрсені беру керек.",
            source: "Fullmetal Alchemist Brotherhood",
            category: "anime"
        ),
        Quote(
            textEn: "No matter how many mistakes you make or how slow you progress, you are still ahead of everyone who isn't trying.",
            textRu: "Сколько бы ошибок ты ни делал и как бы медленно ни продвигался — ты всё равно впереди тех, кто не пытается.",
            textKk: "Қанша қате жіберсең де, қаншалықты баяу жүрсең де — мүлде тырыспайтындардан озғансың.",
            source: "My Hero Academia — All Might",
            category: "anime"
        ),
        Quote(
            textEn: "When you give up, that's when the game ends.",
            textRu: "Когда ты сдаёшься — игра заканчивается.",
            textKk: "Бас тартқанда — ойын аяқталады.",
            source: "Haikyuu — Ittetsu Takeda",
            category: "anime"
        ),
        Quote(
            textEn: "Even in the darkest times, hope is something you give yourself.",
            textRu: "Даже в самые тёмные времена надежда — это то, что ты даришь себе сам.",
            textKk: "Тіпті ең қараңғы уақытта да үміт — өзіңе өзің беретін нәрсе.",
            source: "Avatar: The Last Airbender — Uncle Iroh",
            category: "anime"
        ),
        Quote(
            textEn: "A future is not given to you. It is something you must take for yourself.",
            textRu: "Будущее тебе не дарят. Его нужно взять самому.",
            textKk: "Болашақ саған берілмейді. Оны өзің алуың керек.",
            source: "Steins;Gate — Rintaro Okabe",
            category: "anime"
        ),
        Quote(
            textEn: "Money is just a tool. It becomes meaningful in the hands of someone with purpose.",
            textRu: "Деньги — просто инструмент. Они обретают смысл в руках того, кто знает цель.",
            textKk: "Ақша — тек құрал. Ол мақсаты бар адамның қолында мағынаға ие болады.",
            source: "Re:Zero — Felt",
            category: "anime"
        ),
        Quote(
            textEn: "Once you decide to do something, never give it up. That is the spirit of a true warrior.",
            textRu: "Решив что-то сделать, никогда не сдавайся. Вот в чём дух настоящего воина.",
            textKk: "Бірдеңе жасауды шешіп алсаң, ешқашан бас тартпа. Міне, нағыз жауынгердің рухы осы.",
            source: "Demon Slayer — Tanjiro Kamado",
            category: "anime"
        ),
        Quote(
            textEn: "I want to live a life with no regrets.",
            textRu: "Я хочу прожить жизнь без сожалений.",
            textKk: "Мен өкінішсіз өмір сүргім келеді.",
            source: "Attack on Titan — Hange Zoë",
            category: "anime"
        ),
        Quote(
            textEn: "Even if you feel like you've failed, you can still stand up and try again.",
            textRu: "Даже если кажется, что ты потерпел неудачу — всегда можно встать и попробовать снова.",
            textKk: "Сәтсіздікке ұшырадым деп ойласаң да, тұрып, қайтадан тырысуға болады.",
            source: "My Hero Academia — All Might",
            category: "anime"
        ),
        Quote(
            textEn: "No matter how gifted you are, you alone cannot change the world. But a single step today can.",
            textRu: "Сколь бы одарённым ты ни был, в одиночку мир не изменить. Но один шаг сегодня — может.",
            textKk: "Қаншалықты дарынды болсаң да, жалғыз дүниені өзгерте алмайсың. Бірақ бүгінгі бір қадам — өзгерте алады.",
            source: "L — Death Note",
            category: "anime"
        ),

        // ── Games ──────────────────────────────────────────────────────────────
        Quote(
            textEn: "Praise the sun! For each new dawn brings new opportunity.",
            textRu: "Слава солнцу! Каждый новый рассвет несёт новые возможности.",
            textKk: "Күнді мадақта! Әр таң жаңа мүмкіндіктер әкеледі.",
            source: "Dark Souls — Solaire",
            category: "game"
        ),
        Quote(
            textEn: "The greatest victories are those won without drawing a blade.",
            textRu: "Величайшие победы — те, что одержаны без обнажения клинка.",
            textKk: "Ең ұлы жеңістер — қылыш суырмай қазанылатындар.",
            source: "The Witcher — Geralt of Rivia",
            category: "game"
        ),
        Quote(
            textEn: "Stay determined. Stay focused. Your goals are worth every bit of effort.",
            textRu: "Оставайся решительным. Оставайся сосредоточенным. Твои цели стоят каждого усилия.",
            textKk: "Мақсатты бол. Шоғырлан. Мақсаттарың барлық күш-жігерге лайық.",
            source: "Undertale — Determination",
            category: "game"
        ),
        Quote(
            textEn: "What is better — to be born good, or to overcome your nature and build your wealth through discipline?",
            textRu: "Что лучше — родиться хорошим, или преодолеть свою природу и обрести богатство через дисциплину?",
            textKk: "Жақсы болып туу ма, әлде табиғатыңды жеңіп, тәртіп арқылы байлыққа қол жеткізу ме?",
            source: "Skyrim — Paarthurnax",
            category: "game"
        ),
        Quote(
            textEn: "Everything that has a beginning has an end. Make the journey worthwhile.",
            textRu: "Всё, что имеет начало, имеет конец. Сделай этот путь достойным.",
            textKk: "Басы бар нәрсенің аяғы да болады. Жолды лайықты ет.",
            source: "Nier:Automata — 2B",
            category: "game"
        ),
        Quote(
            textEn: "A dream is just a dream until you work to make it real.",
            textRu: "Мечта остаётся мечтой, пока ты не начнёшь работать над её воплощением.",
            textKk: "Арман — тек арман ғана, оны іске асыруға жұмыс істемесең.",
            source: "Cyberpunk 2077 — Johnny Silverhand",
            category: "game"
        ),
        Quote(
            textEn: "Every coin spent is a choice. Make them wisely.",
            textRu: "Каждая потраченная монета — это выбор. Делай его мудро.",
            textKk: "Жұмсалған әрбір монета — таңдау. Оларды дана жаса.",
            source: "Hollow Knight — Zote the Mighty",
            category: "game"
        ),
        Quote(
            textEn: "The best investment you can make is in yourself.",
            textRu: "Лучшее вложение, которое ты можешь сделать, — это вложение в себя.",
            textKk: "Жасай алатын ең жақсы инвестиция — өзіңе деген инвестиция.",
            source: "Final Fantasy X — Tidus",
            category: "game"
        ),
        Quote(
            textEn: "The world rarely gives you what you want. But it gives you what you earn.",
            textRu: "Мир редко даёт тебе то, чего ты хочешь. Но он даёт то, что ты заслуживаешь.",
            textKk: "Дүние сирек сен қалаған нәрсені береді. Бірақ ол сен тапқан нәрсені береді.",
            source: "Cyberpunk 2077",
            category: "game"
        ),

        // ── Movies ─────────────────────────────────────────────────────────────
        Quote(
            textEn: "Once you do something, you never forget. Even if you can't remember it.",
            textRu: "Однажды сделав что-то, ты никогда этого не забудешь. Даже если не можешь вспомнить.",
            textKk: "Бір рет жасаған нәрсені ешқашан ұмытпайсың. Есіңде болмаса да.",
            source: "Spirited Away — Zeniba",
            category: "movie"
        ),
        Quote(
            textEn: "Just keep swimming. Small progress every day adds up.",
            textRu: "Просто продолжай плыть. Маленький прогресс каждый день — это много.",
            textKk: "Жай жүзе бер. Күн сайынғы кішкентай прогресс — үлкен нәтиже.",
            source: "Finding Nemo — Dory",
            category: "movie"
        ),
        Quote(
            textEn: "The flower that blooms in adversity is the most rare and beautiful of all.",
            textRu: "Цветок, что расцветает в невзгодах — самый редкий и прекрасный из всех.",
            textKk: "Қиыншылықта гүлдейтін гүл — ең сирек және сұлу.",
            source: "Mulan — The Emperor",
            category: "movie"
        ),
        Quote(
            textEn: "Why do we fall? So that we can learn to pick ourselves up.",
            textRu: "Почему мы падаем? Чтобы научиться подниматься.",
            textKk: "Неліктен жығыламыз? Тұруды үйрену үшін.",
            source: "Batman Begins — Alfred",
            category: "movie"
        ),
        Quote(
            textEn: "With great power comes great responsibility — especially financial power.",
            textRu: "Большая сила — большая ответственность. Особенно финансовая.",
            textKk: "Үлкен күш — үлкен жауапкершілік. Әсіресе қаржылық.",
            source: "Spider-Man — Uncle Ben",
            category: "movie"
        ),
        Quote(
            textEn: "It's not about what you have, but who you are and what you do with it.",
            textRu: "Дело не в том, что у тебя есть, а в том, кто ты и что с этим делаешь.",
            textKk: "Маңыздысы — ненің бар екені емес, кім екенің және оны не үшін пайдаланасың.",
            source: "Iron Man — Tony Stark",
            category: "movie"
        ),
        Quote(
            textEn: "Adventure is out there — and preparation makes you ready for it.",
            textRu: "Приключение ждёт тебя — и подготовка сделает тебя к нему готовым.",
            textKk: "Шытырман оқиға сені күтіп тұр — дайындық оған дайын болуға көмектеседі.",
            source: "Up — Russell",
            category: "movie"
        ),
        Quote(
            textEn: "Do, or do not. There is no try — especially with your savings goals.",
            textRu: "Делай, или не делай. Попыток не бывает — особенно в накоплениях.",
            textKk: "Жаса, немесе жасама. Тырысу болмайды — әсіресе жинақтауда.",
            source: "The Empire Strikes Back — Yoda",
            category: "movie"
        ),
    ]

    static var today: Quote {
        let cal = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return quotes[dayOfYear % quotes.count]
    }
}
