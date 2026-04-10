package com.nodecompass.util

import kotlinx.datetime.*

object DateTimeUtil {

    fun currentMonthBounds(): Pair<Long, Long> {
        val now = Clock.System.now()
        val today = now.toLocalDateTime(TimeZone.currentSystemDefault()).date
        val startOfMonth = LocalDate(today.year, today.month, 1)
        val startOfNextMonth = startOfMonth.plus(1, DateTimeUnit.MONTH)

        val startMillis = startOfMonth
            .atStartOfDayIn(TimeZone.currentSystemDefault())
            .toEpochMilliseconds()
        val endMillis = startOfNextMonth
            .atStartOfDayIn(TimeZone.currentSystemDefault())
            .toEpochMilliseconds()

        return startMillis to endMillis
    }

    fun monthBoundsFor(year: Int, month: Month): Pair<Long, Long> {
        val startOfMonth = LocalDate(year, month, 1)
        val startOfNextMonth = startOfMonth.plus(1, DateTimeUnit.MONTH)

        val startMillis = startOfMonth
            .atStartOfDayIn(TimeZone.currentSystemDefault())
            .toEpochMilliseconds()
        val endMillis = startOfNextMonth
            .atStartOfDayIn(TimeZone.currentSystemDefault())
            .toEpochMilliseconds()

        return startMillis to endMillis
    }

    fun formatTimestamp(millis: Long): String {
        val instant = Instant.fromEpochMilliseconds(millis)
        val local = instant.toLocalDateTime(TimeZone.currentSystemDefault())
        val month = local.month.name.take(3).lowercase()
            .replaceFirstChar { it.uppercase() }
        return "${local.dayOfMonth} $month ${local.year}"
    }
}
