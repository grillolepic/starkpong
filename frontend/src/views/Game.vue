<script setup>
import { onMounted } from 'vue';
import { useGameStore, INTERNAL_STATUS } from '@/stores/game';
import { useGameRoomStore } from '../stores/game_room';

const gameStore = useGameStore();
const gameRoomStore = useGameRoomStore();

onMounted(() => {
    gameStore.startGame();
});

</script>

<template>
    <div class="flex column flex-center max-height-without-navbar">
      <div v-if="gameStore.internalStatus == INTERNAL_STATUS.STARTING_SETUP" class="flex column flex-center">
        <div class="inline-spinner"></div>
        <div class="info">Starting the game...</div>
      </div>
      <div v-else-if="gameStore.internalStatus == INTERNAL_STATUS.CONNECTING_WITH_PLAYERS" class="flex column flex-center">
        <div class="inline-spinner"></div>
        <div class="info">Waiting for other players...</div>
      </div>
      <div v-else-if="gameStore.internalStatus == INTERNAL_STATUS.SYNCING" class="flex column flex-center">
        <div class="inline-spinner"></div>
        <div class="info">Syncing last state...</div>
      </div>
      <div v-else-if="gameStore.internalStatus == INTERNAL_STATUS.PLAYING" class="flex column flex-center">
        <div id="PlayersSection" class="flex row">
          <div class="player">PLAYER 1</div>
          <div class="player">PLAYER 2</div>
        </div>
      </div>
    </div>
</template>

<style>
@media (min-width: 1024px) {
  .about {
    min-height: 100vh;
    display: flex;
    align-items: center;
  }
}
</style>
