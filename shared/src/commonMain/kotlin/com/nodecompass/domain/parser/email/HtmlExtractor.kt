package com.nodecompass.domain.parser.email

/**
 * Strips HTML tags and decodes common entities to extract plain text.
 * Lightweight regex-based approach for MVP (no heavy HTML parser dependency).
 */
object HtmlExtractor {

    private val htmlTagRegex = Regex("""<[^>]+>""")
    private val styleBlockRegex = Regex("""<style[^>]*>.*?</style>""", RegexOption.DOT_MATCHES_ALL)
    private val scriptBlockRegex = Regex("""<script[^>]*>.*?</script>""", RegexOption.DOT_MATCHES_ALL)
    private val multiWhitespace = Regex("""\s{2,}""")

    private val htmlEntities = mapOf(
        "&amp;" to "&",
        "&lt;" to "<",
        "&gt;" to ">",
        "&quot;" to "\"",
        "&apos;" to "'",
        "&#39;" to "'",
        "&nbsp;" to " ",
        "&#160;" to " ",
        "&ndash;" to "–",
        "&mdash;" to "—",
        "&copy;" to "©",
        "&reg;" to "®",
        "&trade;" to "™",
        "&dollar;" to "$",
        "&pound;" to "£",
        "&euro;" to "€",
        "&yen;" to "¥",
        "&rupee;" to "₹",
    )

    private val numericEntityRegex = Regex("""&#(\d+);""")

    fun extractText(html: String): String {
        var text = html

        // Remove style and script blocks first
        text = styleBlockRegex.replace(text, " ")
        text = scriptBlockRegex.replace(text, " ")

        // Replace <br>, <p>, <div>, <tr>, <li> with newlines for structure
        text = text.replace(Regex("""<br\s*/?>""", RegexOption.IGNORE_CASE), "\n")
        text = text.replace(Regex("""</(p|div|tr|li|h[1-6])>""", RegexOption.IGNORE_CASE), "\n")
        text = text.replace(Regex("""<(td|th)[^>]*>""", RegexOption.IGNORE_CASE), " | ")

        // Strip remaining HTML tags
        text = htmlTagRegex.replace(text, " ")

        // Decode HTML entities
        for ((entity, replacement) in htmlEntities) {
            text = text.replace(entity, replacement, ignoreCase = true)
        }

        // Decode numeric entities (&#123;) with a BMP range check so that
        // oversized values like &#999999; don't wrap/overflow when cast to Char.
        text = numericEntityRegex.replace(text) { match ->
            val code = match.groupValues[1].toIntOrNull()
            if (code != null && code in 0..0xFFFF) {
                code.toChar().toString()
            } else {
                match.value
            }
        }

        // Clean up whitespace
        text = multiWhitespace.replace(text, " ")
        text = text.lines().joinToString("\n") { it.trim() }.trim()

        return text
    }
}
