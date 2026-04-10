package com.nodecompass.domain.categorizer

import com.nodecompass.data.model.Category

/**
 * Global merchant keyword map for categorizing transactions.
 * Covers major merchants and services worldwide.
 */
val merchantKeywords: Map<Category, List<String>> = mapOf(
    Category.FOOD to listOf(
        // Global food delivery
        "swiggy", "zomato", "uber eats", "ubereats", "doordash", "grubhub",
        "deliveroo", "just eat", "foodpanda", "grab food", "gopuff",
        "postmates", "caviar", "seamless",
        // Restaurants & chains
        "restaurant", "cafe", "pizza", "burger", "dominos", "domino's",
        "mcdonalds", "mcdonald's", "starbucks", "subway", "kfc",
        "taco bell", "chipotle", "wendy's", "popeyes", "chick-fil-a",
        "panera", "panda express", "five guys", "shake shack",
        "nandos", "nando's", "greggs", "pret", "costa coffee",
        "tim hortons", "dunkin", "chaayos", "haldiram", "saravana",
        // Indian food
        "biryani", "dosa", "thali", "dhaba",
        // Bakery / dessert
        "bakery", "dessert", "ice cream", "baskin",
    ),
    Category.GROCERIES to listOf(
        // Global grocery
        "whole foods", "trader joe's", "trader joes", "kroger", "walmart grocery",
        "safeway", "publix", "aldi", "lidl", "costco", "target grocery",
        "tesco", "sainsbury", "asda", "waitrose", "morrisons", "marks spencer food",
        // India
        "bigbasket", "grofers", "blinkit", "jiomart", "dmart", "more supermarket",
        "nature's basket", "spencer", "star bazaar", "reliance fresh",
        // Delivery
        "instacart", "amazon fresh", "ocado", "freshdirect",
        "dunzo", "zepto", "swiggy instamart",
    ),
    Category.TRANSPORT to listOf(
        // Ride hailing
        "uber", "lyft", "ola", "rapido", "bolt", "grab", "gojek",
        "didi", "careem", "via", "curb",
        // Public transport
        "metro", "irctc", "railway", "rail", "bus", "transit",
        "mta", " tfl", "oyster", "clipper",
        // Fuel
        "petrol", "fuel", "gas station", "shell", "bp", "exxon",
        "chevron", "iocl", "bpcl", "hpcl",
        // Parking & tolls
        "parking", "toll", "fastag", "ez-pass",
        // Airlines
        "airline", "airlines", "indigo", "air india", "vistara",
        "delta", "united", "american airlines", "southwest",
        "ryanair", "easyjet", "british airways", "emirates",
    ),
    Category.SHOPPING to listOf(
        // E-commerce
        "amazon", "flipkart", "myntra", "ajio", "nykaa",
        "meesho", "ebay", "etsy", "wish",
        "walmart", "target", "best buy", "apple store",
        "ikea", "h&m", "zara", "uniqlo", "asos", "shein",
        // Department stores
        "macy's", "nordstrom", "john lewis", "selfridges",
        "marks spencer", "primark",
    ),
    Category.SUBSCRIPTIONS to listOf(
        // Streaming
        "netflix", "spotify", "hotstar", "disney+", "disney plus",
        "hulu", "hbo max", "prime video", "apple tv",
        "youtube premium", "youtube music", "crunchyroll", "peacock",
        "paramount+", "paramount plus",
        // Software / cloud
        "apple.com/bill", "google play", "google one", "icloud",
        "adobe", "notion", "chatgpt", "openai", "microsoft 365",
        "dropbox", "evernote", "canva", "figma", "slack",
        "github", "gitlab", "aws", "heroku", "vercel",
        // News / reading
        "medium", "substack", "kindle unlimited",
        "new york times", "washington post", "economist",
        // Fitness / wellness
        "headspace", "calm", "peloton", "strava",
    ),
    Category.BILLS to listOf(
        // Utilities
        "electricity", "electric", "water bill", "gas bill",
        "utility", "utilities", "power", "sewage",
        // Internet / phone
        "broadband", "internet", "wifi", "fiber",
        "jio", "airtel", "vi ", "vodafone", "bsnl",
        "t-mobile", "verizon", "at&t", "sprint",
        "ee ", "three ", "o2 ", "sky ",
        "comcast", "xfinity", "spectrum", "cox",
        // TV
        "tata play", "dish tv", "cable",
        // Insurance
        "insurance", "premium",
        // Rent / housing
        "rent", "mortgage", "housing",
    ),
    Category.ENTERTAINMENT to listOf(
        "bookmyshow", "pvr", "inox", "cinema", "movie",
        "amc", "regal", "cineworld", "odeon",
        "concert", "ticket", "ticketmaster", "stubhub",
        "eventbrite", "live nation",
        "gaming", "steam", "playstation", "xbox", "nintendo",
        "epic games", "twitch",
    ),
    Category.HEALTH to listOf(
        "pharmacy", "apollo", "1mg", "pharmeasy", "netmeds",
        "hospital", "clinic", "diagnostic", "pathology", "lab test",
        "dr ", "doctor", "dental", "dentist", "optician",
        "cvs", "walgreens", "boots pharmacy", "rite aid",
        "gym", "fitness", "yoga",
    ),
    Category.EDUCATION to listOf(
        "udemy", "coursera", "skillshare", "masterclass",
        "linkedin learning", "pluralsight",
        "university", "college", "school", "tuition",
        "book", "books", "textbook",
    ),
    Category.ATM to listOf(
        "atm", "cash withdrawal", "cash wdl", "cash wd",
    ),
    Category.TRANSFERS to listOf(
        "neft", "imps", "rtgs", "upi", "transfer to", "fund transfer",
        "wire transfer", "bank transfer", "zelle", "venmo", "cashapp",
        "paypal", "wise", "remittance",
    ),
)
