import Foundation

struct Quote {
    let text: String
    let source: String
    let category: String // "anime", "game", "movie"
}

enum DailyQuoteStore {
    static let quotes: [Quote] = [
        // Anime
        Quote(text: "Hard work is worthless for those that don't believe in themselves.", source: "Naruto — Naruto Uzumaki", category: "anime"),
        Quote(text: "It's not the face that makes someone a monster; it's the choices they make with their lives.", source: "Naruto — Naruto Uzumaki", category: "anime"),
        Quote(text: "If you don't take risks, you can't create a future.", source: "One Piece — Monkey D. Luffy", category: "anime"),
        Quote(text: "Wealth is found not in what you own, but in what you have given away.", source: "One Piece — Whitebeard", category: "anime"),
        Quote(text: "The world isn't perfect. But it's there for us, doing the best it can.", source: "Fullmetal Alchemist — Roy Mustang", category: "anime"),
        Quote(text: "A lesson without pain is meaningless. For you cannot gain something without sacrificing something else.", source: "Fullmetal Alchemist — Edward Elric", category: "anime"),
        Quote(text: "Equivalent exchange: to gain something you must sacrifice something of equal value.", source: "Fullmetal Alchemist Brotherhood", category: "anime"),
        Quote(text: "The only ones who should kill are those who are prepared to be killed.", source: "Code Geass — Lelouch", category: "anime"),
        Quote(text: "No matter how many mistakes you make or how slow you progress, you are still way ahead of everyone who isn't trying.", source: "My Hero Academia — All Might", category: "anime"),
        Quote(text: "There's nothing special about being born. Not a thing. Most of the universe is just gas and rock.", source: "My Hero Academia — Izuku Midoriya", category: "anime"),
        Quote(text: "Even if you feel like you've failed, you can still stand up and try again.", source: "My Hero Academia — All Might", category: "anime"),
        Quote(text: "When you give up, that's when the game ends.", source: "Haikyuu — Ittetsu Takeda", category: "anime"),
        Quote(text: "People's lives don't end when they die. It ends when they lose faith.", source: "Naruto — Itachi Uchiha", category: "anime"),
        Quote(text: "Protecting a friend's future is worth more than any gold.", source: "Attack on Titan — Armin Arlert", category: "anime"),
        Quote(text: "I want to live a life with no regrets.", source: "Attack on Titan — Hange Zoë", category: "anime"),
        Quote(text: "Even in the darkest times, hope is something you give yourself.", source: "Avatar: The Last Airbender — Uncle Iroh", category: "anime"),
        Quote(text: "Sometimes it's the people who have nothing who are willing to share everything.", source: "Fullmetal Alchemist Brotherhood", category: "anime"),
        Quote(text: "The moment you think of giving up, think of the reason why you held on so long.", source: "Naruto", category: "anime"),
        Quote(text: "Don't give up. There's no shame in falling down. True shame is to not stand up again.", source: "Shintaro Midorima", category: "anime"),
        Quote(text: "If you only ever do what you can, you'll only ever be what you are.", source: "Fullmetal Alchemist — Edward Elric", category: "anime"),
        Quote(text: "The strong live and the weak die. But there is grace in knowing why you persevere.", source: "Re:Zero — Subaru Natsuki", category: "anime"),
        Quote(text: "No matter how gifted you are, you alone cannot change the world. But a single step today can.", source: "L — Death Note", category: "anime"),
        Quote(text: "A future is not given to you. It is something you must take for yourself.", source: "Steins;Gate — Rintaro Okabe", category: "anime"),
        Quote(text: "The decision is not yours alone. Think of those who depend on you.", source: "Steins;Gate — Makise Kurisu", category: "anime"),
        Quote(text: "Money is just a tool. It becomes meaningful in the hands of someone with purpose.", source: "Re:Zero — Felt", category: "anime"),
        Quote(text: "Once you decide to do something, never give it up. That is the spirit of a true warrior.", source: "Demon Slayer — Tanjiro Kamado", category: "anime"),

        // Games
        Quote(text: "Fear not the darkness, but welcome its embrace.", source: "Dark Souls", category: "game"),
        Quote(text: "Praise the sun! For each new dawn brings new opportunity.", source: "Dark Souls — Solaire", category: "game"),
        Quote(text: "The greatest victories are those won without drawing a blade.", source: "The Witcher — Geralt of Rivia", category: "game"),
        Quote(text: "Evil is evil. Lesser, greater, middling, it's all the same.", source: "The Witcher — Geralt of Rivia", category: "game"),
        Quote(text: "Some have eyes but cannot see; some have wealth but cannot spend it wisely.", source: "Final Fantasy VII — Aerith", category: "game"),
        Quote(text: "Even if the morrow is barren of promises, nothing shall forestall my return.", source: "Final Fantasy XIV", category: "game"),
        Quote(text: "Stay determined. Stay focused. Your goals are worth every bit of effort.", source: "Undertale — Determination", category: "game"),
        Quote(text: "It's dangerous to go alone. But a plan and patience make the journey easier.", source: "The Legend of Zelda", category: "game"),
        Quote(text: "We stand upon the shoulders of those who came before. Honor their sacrifices with your success.", source: "Skyrim — Paarthurnax", category: "game"),
        Quote(text: "What is better — to be born good, or to overcome your nature and build your wealth through discipline?", source: "Skyrim — Paarthurnax", category: "game"),
        Quote(text: "Some plants grow in the harshest soil. So too can your savings grow in difficult times.", source: "Stardew Valley", category: "game"),
        Quote(text: "Everything that has a beginning has an end. Make the journey worthwhile.", source: "Nier:Automata — 2B", category: "game"),
        Quote(text: "Memories are the only things that truly belong to you.", source: "Nier:Automata — 9S", category: "game"),
        Quote(text: "The purpose of life is to live it, not merely to survive.", source: "Nier:Automata — A2", category: "game"),
        Quote(text: "Even the longest journey begins with a single step — and a single coin saved.", source: "Final Fantasy VII — Cloud", category: "game"),
        Quote(text: "Night City always takes more than it gives. But the prepared never go empty-handed.", source: "Cyberpunk 2077 — V", category: "game"),
        Quote(text: "A dream is just a dream until you work to make it real.", source: "Cyberpunk 2077 — Johnny Silverhand", category: "game"),
        Quote(text: "The world rarely gives you what you want. But it gives you what you earn.", source: "Cyberpunk 2077", category: "game"),
        Quote(text: "To conquer fear is the beginning of wisdom, and the beginning of building real wealth.", source: "Dune — Paul Atreides", category: "game"),
        Quote(text: "True strength is measured not by what you accumulate, but by what you endure.", source: "Hollow Knight — The Knight", category: "game"),
        Quote(text: "In the void, only purpose keeps you moving forward.", source: "Hollow Knight", category: "game"),
        Quote(text: "Every coin spent is a choice. Make them wisely.", source: "Hollow Knight — Zote the Mighty", category: "game"),
        Quote(text: "The best investment you can make is in yourself.", source: "Final Fantasy X — Tidus", category: "game"),

        // Movies
        Quote(text: "Once you do something, you never forget. Even if you can't remember it.", source: "Spirited Away — Zeniba", category: "movie"),
        Quote(text: "You can't buy what matters most. But you can build towards it.", source: "Spirited Away — Lin", category: "movie"),
        Quote(text: "The humans have forgotten what it means to truly live within their means.", source: "Princess Mononoke — Lady Eboshi", category: "movie"),
        Quote(text: "Nature gives freely; only those who respect it receive its full gifts.", source: "Princess Mononoke — San", category: "movie"),
        Quote(text: "Just keep swimming. Small progress every day adds up.", source: "Finding Nemo — Dory", category: "movie"),
        Quote(text: "In every job that must be done, there is an element of fun — including budgeting.", source: "Mary Poppins", category: "movie"),
        Quote(text: "To infinity and beyond — that is the spirit of any financial goal worth setting.", source: "Toy Story — Buzz Lightyear", category: "movie"),
        Quote(text: "Adventure is out there — and preparation makes you ready for it.", source: "Up — Charles Muntz", category: "movie"),
        Quote(text: "The flower that blooms in adversity is the most rare and beautiful of all.", source: "Mulan — The Emperor", category: "movie"),
        Quote(text: "Life is like a box of chocolates: your budget determines what you get.", source: "Forrest Gump", category: "movie"),
        Quote(text: "Do, or do not. There is no try — especially with your savings goals.", source: "The Empire Strikes Back — Yoda", category: "movie"),
        Quote(text: "Why do we fall? So that we can learn to pick ourselves up.", source: "Batman Begins — Alfred", category: "movie"),
        Quote(text: "With great power comes great responsibility — especially financial power.", source: "Spider-Man — Uncle Ben", category: "movie"),
        Quote(text: "It's not about what you have, but about who you are and what you do with it.", source: "Iron Man — Tony Stark", category: "movie"),
    ]

    static var today: Quote {
        let cal = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return quotes[dayOfYear % quotes.count]
    }
}
