<script setup>
import { onMounted, onUnmounted } from 'vue';
import { useGameStore, INTERNAL_STATUS } from '@/stores/game';
import { useGameRoomStore } from '../stores/game_room';

const gameStore = useGameStore();
const gameRoomStore = useGameRoomStore();

onMounted(() => {
  gameStore.startGame();
});

onUnmounted(() => {
  gameStore.reset();
})

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
      <div id="PlayersSection" class="flex row max-width">
        <div class="player flex column flex-center">
          <div :class="{ 'bold': (gameRoomStore.myPlayerNumber == 0) }">{{ (gameRoomStore.myPlayerNumber == 0) ? 'YOU' :
            'PLAYER 1' }}</div>
          <div class="score">{{ gameStore.currentState.score_0 }}</div>
        </div>
        <div class="player flex column flex-center">
          <div :class="{ 'bold': (gameRoomStore.myPlayerNumber == 1) }">{{ (gameRoomStore.myPlayerNumber == 1) ? 'YOU' :
            'PLAYER 2' }}</div>
          <div class="score">{{ gameStore.currentState.score_1 }}</div>
        </div>
      </div>
      <div id="GameSection" class="flex row flex-center max-width">
        <canvas id="gameCanvas"></canvas>
      </div>
      <div id="DataSection" class="flex row">
        <div class="flex column data_section">
          <div class="small">CHECKPOINT: <span class="bold">{{ gameStore.currentState.turn }}</span></div>
          <div class="smaller">0x0</div>
          <div class="smaller">0x0</div>
          <div class="smaller">0x0</div>
          <div class="smaller">0x0</div>
        </div>
        <div class="flex column data_section">
          <div class="small turn">TURN: <span class="bold">{{ gameStore.currentState.turn }}</span></div>
          <div class="smaller turn">0x0</div>
          <div class="smaller turn">0x0</div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
  setInterval(() => {
    var canvas = document.getElementById("gameCanvas");
    console.log(canvas);
    if (canvas != undefined && canvas != null) {
      var ctx = canvas.getContext("2d");

        ctx.fillStyle = "#FF0000";
        ctx.fillRect(0, 0, 16, 9);
    }

  }, 5000);
</script>

<style>
#PlayersSection {
  justify-content: space-between;
  margin-bottom: 15px;
  height: 50px;
  width: 750px;
}

.score {
  font-size: 42px;
  font-family: 'Monoton', cursive;
}

#gameCanvas {
  width: 800px;
  height: 600px;
  border-radius: 0.375rem;
  border: 1px solid var(--white);
  background-color: var(--black);
}

.small {
  margin-bottom: 5px;
}

#DataSection {
  margin-top: 10px;
}

.data_section {
  width: 400px;
}

.turn {
  text-align: right;
}

.smaller {
  font-size: 8px;
  color: var(--grey-over-black);
  margin-top:2px;
}
</style>
