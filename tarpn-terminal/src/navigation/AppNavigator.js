import React, { useContext } from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { NavigationContainer, DarkTheme } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons'; // Expo comes with vector icons
import MonitorScreen from '../screens/MonitorScreen';
import ChatScreen from '../screens/ChatScreen';
import BBSScreen from '../screens/BBSScreen';
import NodeScreen from '../screens/NodeScreen';
import StatsScreen from '../screens/StatsScreen';
import SettingsScreen from '../screens/SettingsScreen';
import { AppProvider, AppContext } from '../context/AppContext';
import { StatusBar } from 'expo-status-bar';

const Tab = createBottomTabNavigator();

// Custom Theme
const MyDarkTheme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    background: '#1e1e1e',
    card: '#252525',
    text: '#ffffff',
    border: '#333',
    primary: '#4ade80',
  },
};

// Inner component that uses the context
function TabNavigator() {
  const { features } = useContext(AppContext);

  return (
    <Tab.Navigator
        screenOptions={({ route }) => ({
            headerStyle: { backgroundColor: '#252525' },
            headerTintColor: '#fff',
            tabBarActiveTintColor: '#4ade80',
            tabBarInactiveTintColor: '#888',
            tabBarStyle: {
                backgroundColor: '#252525',
                borderTopColor: '#333'
            },
            tabBarIcon: ({ focused, color, size }) => {
                let iconName;

                if (route.name === 'Monitor') {
                    iconName = focused ? 'list' : 'list-outline';
                } else if (route.name === 'Chat') {
                    iconName = focused ? 'chatbubbles' : 'chatbubbles-outline';
                } else if (route.name === 'BBS') {
                    iconName = focused ? 'mail' : 'mail-outline';
                } else if (route.name === 'Node') {
                    iconName = focused ? 'terminal' : 'terminal-outline';
                } else if (route.name === 'Stats') {
                    iconName = focused ? 'bar-chart' : 'bar-chart-outline';
                } else if (route.name === 'Settings') {
                    iconName = focused ? 'settings' : 'settings-outline';
                }

                // You can return any component that you like here!
                return <Ionicons name={iconName} size={size} color={color} />;
            },
        })}
    >
        <Tab.Screen name="Monitor" component={MonitorScreen} options={{headerShown: false}} />
        {features.chat && (
            <Tab.Screen name="Chat" component={ChatScreen} options={{headerShown: false}} />
        )}
        {features.bbs && (
            <Tab.Screen name="BBS" component={BBSScreen} options={{headerShown: false}} />
        )}
        {features.node && (
            <Tab.Screen name="Node" component={NodeScreen} options={{headerShown: false}} />
        )}
        <Tab.Screen name="Stats" component={StatsScreen} />
        <Tab.Screen name="Settings" component={SettingsScreen} />
    </Tab.Navigator>
  );
}

export default function AppNavigator() {
  return (
    <AppProvider>
        <NavigationContainer theme={MyDarkTheme}>
            <StatusBar style="light" />
            <TabNavigator />
        </NavigationContainer>
    </AppProvider>
  );
}
