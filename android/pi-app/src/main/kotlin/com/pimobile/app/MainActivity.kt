package com.pimobile.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.pimobile.app.ui.chat.ChatScreen
import com.pimobile.app.ui.session.SessionListScreen
import com.pimobile.app.ui.settings.SettingsScreen
import com.pimobile.app.ui.theme.PiMobileTheme
import com.pimobile.tools.FileAccessManager

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        FileAccessManager.instance.configure(this)
        enableEdgeToEdge()
        setContent {
            PiMobileTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    AppNavigation()
                }
            }
        }
    }
}

@Composable
fun AppNavigation() {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = "sessions") {
        composable("sessions") {
            SessionListScreen(
                onSessionClick = { sessionId ->
                    navController.navigate("chat/$sessionId")
                },
                onNewSession = {
                    navController.navigate("chat/new")
                },
                onSettingsClick = {
                    navController.navigate("settings")
                }
            )
        }
        composable("chat/{sessionId}") { backStackEntry ->
            val sessionId = backStackEntry.arguments?.getString("sessionId") ?: "new"
            ChatScreen(
                sessionId = sessionId,
                onBack = { navController.popBackStack() }
            )
        }
        composable("settings") {
            SettingsScreen(
                onBack = { navController.popBackStack() }
            )
        }
    }
}
