package me.timeto.shared.vm

import io.ktor.client.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.utils.io.core.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import me.timeto.shared.*
import me.timeto.shared.db.*

class AppVM : __VM<AppVM.State>() {

    data class State(
        val isAppReady: Boolean,
    )

    override val state = MutableStateFlow(
        State(
            isAppReady = false
        )
    )

    override fun onAppear() {
        scopeVM().launchEx {

            initKmmDeferred.await()

            if (!DI.isLateInitInitialized())
                fillInitData()

            // todo remove ofter this triggers once ~2023.11.21
            val kvNamesToDelete = setOf("EVENTS_HISTORY", "CALENDAR_HISTORY", "IS_SHOW_README_ON_MAIN")
            KvDb.getAll()
                .filter { it.key in kvNamesToDelete }
                .map { it.backupable__delete() }

            state.update { it.copy(isAppReady = true) }

            ///

            IntervalModel
                .getLastOneOrNullFlow()
                .filterNotNull()
                .onEachExIn(this) { lastInterval ->
                    ActivityDb.syncTimeHints()
                    rescheduleNotifications()
                    performShortcut(lastInterval, secondsLimit = 3)
                    keepScreenOnStateFlow.emit(lastInterval.getActivityDI().keepScreenOn)
                }

            launchEx {
                while (true) {
                    /**
                     * Not delayToNextMinute(extraMls = 1_000L):
                     * - No need to wait after daytime changes;
                     * - No need to wait after backup restore.
                     */
                    try {
                        delay(1_000L)
                    } catch (e: CancellationException) {
                        break // On app closing
                    }
                    try {
                        syncTmrw()
                        syncTodayEvents()
                        syncTodayRepeating()
                    } catch (e: Throwable) {
                        reportApi("AppVM sync today error:$e")
                        delay(300_000L)
                    }
                }
            }

            launchEx {
                // Delay to not load the system at startup. But not too long
                // because some data may be needed soon, like feedback subject.
                delay(500L)
                while (true) {
                    ping()
                    try {
                        delay(10 * 60 * 1_000L) // 10 min
                    } catch (e: CancellationException) {
                        break // On app closing
                    }
                }
            }
        }
    }

    fun onNotificationsPermissionReady(delayMls: Long) {
        scopeVM().launchEx {
            delay(delayMls)
            rescheduleNotifications()
        }
    }
}

private fun performShortcut(
    interval: IntervalModel,
    secondsLimit: Int,
) {
    if ((interval.id + secondsLimit) < time())
        return

    val shortcut: ShortcutModel? =
        interval.note?.textFeatures()?.shortcuts?.firstOrNull()
        ?: interval.getActivityDI().name.textFeatures().shortcuts.firstOrNull()

    shortcut?.performUI()
}

///
/// Ping

private var pingLastDay: Int? = null
private suspend fun ping() {
    if (isFDroid)
        return

    val today = UnixTime().localDay
    if (pingLastDay == today)
        return

    try {
        HttpClient().use { client ->
            val httpResponse = client.get("https://api.timeto.me/ping") {
                url {
                    parameters.append("password", getsertTokenPassword())
                    appendDeviceData()
                }
            }
            val plainJson = httpResponse.bodyAsText()
            val j = Json.parseToJsonElement(plainJson).jsonObject
            if (j.getString("status") != "success")
                throw Exception("status != success\n$plainJson")
            val jData = j.jsonObject["data"]!!.jsonObject
            SecureLocalStorage__Key.token.upsert(jData.getString("token"))
            SecureLocalStorage__Key.feedback_subject.upsert(jData.getString("feedback_subject"))
            pingLastDay = today // After success
        }
    } catch (e: Throwable) {
        reportApi("AppVM ping() exception:\n$e")
    }
}

@Throws(SecureLocalStorage__Exception::class)
private fun getsertTokenPassword(): String {
    val oldPassword = SecureLocalStorage__Key.token_password.getOrNull()
    if (oldPassword != null)
        return oldPassword

    val chars = ('0'..'9') + ('a'..'z') + ('A'..'Z') + ("!@#%^&*()_+".toList())
    val newPassword = (1..15).map { chars.random() }.joinToString("")
    SecureLocalStorage__Key.token_password.upsert(newPassword)
    return newPassword
}

///
/// Sync today

private var syncTodayRepeatingLastDay: Int? = null
private suspend fun syncTodayRepeating() {
    val todayWithOffset = UnixTime(time() - dayStartOffsetSeconds()).localDay
    // To avoid unnecessary checks. It works without that.
    if (syncTodayRepeatingLastDay == todayWithOffset)
        return
    RepeatingModel.syncTodaySafe(todayWithOffset)
    // In case on error while syncTodaySafe()
    syncTodayRepeatingLastDay = todayWithOffset
}

private var syncTodayEventsLastDay: Int? = null
private suspend fun syncTodayEvents() {
    // GD "Day Start Offset" -> "Using for Events"
    val todayNoOffset = UnixTime().localDay
    // To avoid unnecessary checks. It works without that.
    if (syncTodayEventsLastDay == todayNoOffset)
        return
    EventDb.syncTodaySafe(todayNoOffset)
    // In case on error while syncTodaySafe()
    syncTodayEventsLastDay = todayNoOffset
}

private fun syncTmrw() {
    // DI to performance
    // Using .localDayWithDayStart() everywhere
    val utcOffsetDS = localUtcOffsetWithDayStart
    val todayDay = UnixTime(utcOffset = utcOffsetDS).localDay
    val todayFolder = DI.getTodayFolder()
    DI.tasks
        .filter { it.isTmrw && (it.unixTime(utcOffset = utcOffsetDS).localDay < todayDay) }
        .forEach { task ->
            launchExDefault {
                task.upFolder(
                    newFolder = todayFolder,
                    replaceIfTmrw = false // No matter
                )
            }
        }
}

//////

private suspend fun fillInitData() {
    try {
        /**
         * In iOS, the data in the keychain is saved even after uninstalling
         * the app, when initializing it is better to clean it. Otherwise:
         * - Reinstalling will not always "save" in any unclear situation;
         * - If it applies to different devices, there may be more than one
         *   device for one user.
         */
        SecureLocalStorage__Key.values().forEach { it.upsert(null) }
        syncTodayEventsLastDay = null
        syncTodayRepeatingLastDay = null
        pingLastDay = null
    } catch (e: Throwable) {
        reportApi("fillInitData() exception:\n$e")
    }

    // TRICK time() only for SMDAY
    TaskFolderModel.addRaw(TaskFolderModel.ID_TODAY, "Today", 1)
    TaskFolderModel.addTmrw()
    TaskFolderModel.addRaw(time(), "SMDAY", 3)

    val colorsWheel = Wheel(ActivityDb.colors)
    val cGreen = colorsWheel.next()
    val cBlue = colorsWheel.next()
    val cRed = colorsWheel.next()
    val cYellow = colorsWheel.next()
    val cPurple = colorsWheel.next()

    val goals = listOf<ActivityDb.Goal>()
    val defData = ActivityModel__Data.buildDefault()
    val aNormal = ActivityDb.TYPE.NORMAL
    val actMed = ActivityDb.addWithValidation("Meditation", "🧘‍♀️", 20 * 60, 1, aNormal, cYellow, defData, true, goals)
    val actWork = ActivityDb.addWithValidation("Work", "📁", 40 * 60, 2, aNormal, cBlue, defData, true, goals)
    ActivityDb.addWithValidation("Hobby", "🎸", 3600, 3, aNormal, cRed, defData, true, goals)
    val actPd = ActivityDb.addWithValidation("Personal development", "📖", 30 * 60, 4, aNormal, cPurple, defData, true, goals)
    val actEx = ActivityDb.addWithValidation("Exercises / Health", "💪", 20 * 60, 5, aNormal, colorsWheel.next(), defData, false, goals)
    ActivityDb.addWithValidation("Walk", "👟", 30 * 60, 6, aNormal, colorsWheel.next(), defData, false, goals)
    val actGr = ActivityDb.addWithValidation("Getting ready", "🚀", 30 * 60, 7, aNormal, colorsWheel.next(), defData, true, goals)
    ActivityDb.addWithValidation("Sleep / Rest", "😴", 8 * 3600, 8, aNormal, cGreen, defData, false, goals)
    val actOther = ActivityDb.addWithValidation("Other", "💡", 3600, 9, ActivityDb.TYPE.OTHER, colorsWheel.next(), defData, true, goals)

    val interval = IntervalModel.addWithValidation(30 * 60, actPd, null)
    DI.fillLateInit(interval, interval) // To 100% ensure

    val todayDay = UnixTime().localDay
    fun prepRep(title: String, activity: ActivityDb, timerMin: Int): String =
        title.textFeatures().copy(activity = activity, timer = timerMin * 60).textWithFeatures()
    RepeatingModel.addWithValidation(prepRep("Exercises", actEx, 30), RepeatingModel.Period.EveryNDays(1), todayDay, null, false)
    RepeatingModel.addWithValidation(prepRep("Meditation", actMed, 20), RepeatingModel.Period.EveryNDays(1), todayDay, null, false)
    RepeatingModel.addWithValidation(prepRep("Small tasks", actOther, 30), RepeatingModel.Period.EveryNDays(1), todayDay, null, false)
    RepeatingModel.addWithValidation(prepRep("Getting ready", actGr, 20), RepeatingModel.Period.EveryNDays(1), todayDay, null, false)
    RepeatingModel.addWithValidation(prepRep("Weekly plan", actWork, 20), RepeatingModel.Period.DaysOfWeek(listOf(0)), todayDay, null, false)
}
