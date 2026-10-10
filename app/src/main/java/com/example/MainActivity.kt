package com.example

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.example.ui.screens.*
import com.example.ui.theme.CrazeChatTheme
import com.example.viewmodel.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Prevent black background glitch when keyboard or window resizes
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(0xFFFFFFFF.toInt()))
        
        enableEdgeToEdge()

        setContent {
            val authViewModel: AuthViewModel = viewModel()
            val themeMode by authViewModel.themeMode.collectAsState()
            val darkTheme = themeMode == "dark"

            // Keep system window background in sync with theme to prevent black keyboard flicker
            LaunchedEffect(darkTheme) {
                window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(
                    if (darkTheme) 0xFF0F172A.toInt() else 0xFFFFFFFF.toInt()
                ))
            }

            CrazeChatTheme(darkTheme = darkTheme) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val userId by authViewModel.userIdFlow.collectAsState(initial = "")
                    val navController = rememberNavController()

                    val startDestination = if (userId.isNullOrEmpty()) "welcome" else "home"

                    LaunchedEffect(userId) {
                        if (userId.isNullOrEmpty()) {
                            navController.navigate("welcome") {
                                popUpTo(0) { inclusive = true }
                            }
                        }
                    }

                    NavHost(navController = navController, startDestination = startDestination) {
                        composable("welcome") {
                            WelcomeScreen(
                                viewModel = authViewModel,
                                onLogin = { profile ->
                                    authViewModel.switchProfile(profile)
                                    navController.navigate("home") {
                                        popUpTo("welcome") { inclusive = true }
                                    }
                                },
                                onCreateAccount = {
                                    navController.navigate("register")
                                }
                            )
                        }
                        composable("register") {
                            RegisterScreen(
                                viewModel = authViewModel,
                                onRegistered = {
                                    navController.navigate("home") {
                                        popUpTo("register") { inclusive = true }
                                    }
                                },
                                onNavigateToLogin = {
                                    navController.navigate("login")
                                }
                            )
                        }
                        composable("login") {
                            LoginScreen(
                                viewModel = authViewModel,
                                onLoggedIn = {
                                    navController.navigate("home") {
                                        popUpTo("login") { inclusive = true }
                                    }
                                },
                                onNavigateToRegister = {
                                    navController.popBackStack()
                                }
                            )
                        }
                        composable("home") {
                            val homeViewModel: HomeViewModel = viewModel()
                            HomeScreen(
                                viewModel = homeViewModel,
                                onChatClicked = { chatId ->
                                    navController.navigate("chat/$chatId")
                                },
                                onProfileClicked = { navController.navigate("profile") },
                                onSecurityInfoClicked = { navController.navigate("security") },
                                onSettingsClicked = { navController.navigate("settings") },
                                onRegisterSecondUser = { navController.navigate("register") }
                            )
                        }
                        composable(
                            route = "chat/{chatId}",
                            arguments = listOf(navArgument("chatId") { type = NavType.StringType })
                        ) { backStackEntry ->
                            val chatId = backStackEntry.arguments?.getString("chatId") ?: ""
                            val chatViewModel: ChatViewModel = viewModel(
                                factory = object : androidx.lifecycle.ViewModelProvider.Factory {
                                    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
                                        return ChatViewModel(application, chatId) as T
                                    }
                                }
                            )
                            ChatScreen(
                                viewModel = chatViewModel,
                                onBackClicked = { navController.popBackStack() }
                            )
                        }
                        composable("profile") {
                            val profileViewModel: ProfileViewModel = viewModel()
                            ProfileScreen(
                                viewModel = profileViewModel,
                                onBackClicked = { navController.popBackStack() }
                            )
                        }
                        composable("security") {
                            SecurityInfoScreen(
                                onBackClicked = { navController.popBackStack() }
                            )
                        }
                        composable("settings") {
                            SettingsScreen(
                                authViewModel = authViewModel,
                                onBackClicked = { navController.popBackStack() },
                                onRegisterSecondUser = { navController.navigate("register") }
                            )
                        }
                    }
                }
            }
        }
    }
}
