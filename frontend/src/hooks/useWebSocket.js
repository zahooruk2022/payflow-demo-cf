import { useEffect, useRef } from 'react'
import { Client } from '@stomp/stompjs'
import SockJS from 'sockjs-client'

export function useWebSocket({ onTransaction, onFraudAlert, onStats, onConnected }) {
  const clientRef = useRef(null)

  useEffect(() => {
    const client = new Client({
      // Uses current host so it works on CF (any route) and local dev (Vite proxy handles /ws)
      webSocketFactory: () => new SockJS(`${window.location.origin}/ws`),
      reconnectDelay: 3000,
      onConnect: () => {
        onConnected?.(true)
        client.subscribe('/topic/transactions', msg => {
          onTransaction?.(JSON.parse(msg.body))
        })
        client.subscribe('/topic/fraud-alerts', msg => {
          onFraudAlert?.(JSON.parse(msg.body))
        })
        client.subscribe('/topic/stats', msg => {
          onStats?.(JSON.parse(msg.body))
        })
      },
      onDisconnect: () => onConnected?.(false),
      onStompError: () => onConnected?.(false),
    })

    client.activate()
    clientRef.current = client

    return () => { client.deactivate() }
  }, []) // intentionally empty — stable callbacks via refs if needed
}
