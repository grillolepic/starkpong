<script setup>
import { onMounted, onUnmounted } from 'vue';
import { useGameStore, INTERNAL_STATUS } from '@/stores/game';
import { useGameRoomStore } from '../stores/game_room';

const gameStore = useGameStore();
const gameRoomStore = useGameRoomStore();
let _drawInterval = null;
let canvas = null;
let ctx = null;

onMounted(() => {
  gameStore.startGame();
  _drawInterval = setInterval(draw, 33);
  document.addEventListener("keydown", handleKeyboardDown);
  document.addEventListener("keyup", handleKeyboardUp);
});

onUnmounted(() => {
  gameStore.reset();
  clearInterval(_drawInterval);
  document.removeEventListener("keydown", handleKeyboardDown);
  document.addEventListener("keyup", handleKeyboardUp);
});

function handleKeyboardDown(event) {
  if (event.keyCode == 38) {
    gameStore.handleKeyDown(true);
  } else if (event.keyCode == 40) {
    gameStore.handleKeyDown(false);
  }
}

function handleKeyboardUp(event) {
  if (event.keyCode == 38) {
    gameStore.handleKeyDown(true);
  } else if (event.keyCode == 40) {
    gameStore.handleKeyDown(false);
  }
}

function draw() {
  if (gameStore.internalStatus != INTERNAL_STATUS.PLAYING) {
    ctx = null;
    canvas = null;
    return;
  }

  if (ctx == null || canvas == null) {
    canvas = document.getElementById("gameCanvas");
    if (canvas != undefined && canvas != null) {
      ctx = canvas.getContext("2d");
    }
  }

  let currentState = gameStore.gameStateForScreen;

  if (currentState != null && currentState != undefined) {

    ctx.fillStyle = "#FFFFFF";
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    //Paddle 0
    ctx.fillRect(0, currentState.paddle_0.y - (currentState.paddle_0.size / 2.0), 20, currentState.paddle_0.size);

    //Paddle 1
    ctx.fillRect(780, currentState.paddle_1.y - (currentState.paddle_1.size / 2.0), 20, currentState.paddle_1.size);

    //Ball
    if (gameStore.paused) {
      let ts = Math.floor(Date.now() / 500);
      if (ts % 2 == 0) {
        ctx.fillRect(
          currentState.ball.x - (currentState.ball.size / 2.0),
          currentState.ball.y - (currentState.ball.size / 2.0),
          currentState.ball.size, currentState.ball.size);
      }
    } else {
      ctx.fillRect(
        currentState.ball.x - (currentState.ball.size / 2.0),
        currentState.ball.y - (currentState.ball.size / 2.0),
        currentState.ball.size, currentState.ball.size);
    }
  }
}

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
        <div v-if="gameStore.paused" style="width: 20px; height: 20px; background-color: yellow; border-radius: 20px;">

        </div>
      </div>
      <div id="GameSection" class="flex row flex-center max-width">
        <canvas id="gameCanvas" width="800" height="600"></canvas>
      </div>
      <div id="DataSection" class="flex row">
        <div class="flex column data_section">
          <div class="small">CHECKPOINT: <span class="bold">{{ gameStore.checkpoint.data.turn }}</span></div>
          <div class="smaller">{{ gameStore.lastCheckpointSignature[0] }}</div>
          <div class="smaller">{{ gameStore.lastCheckpointSignature[1] }}</div>
          <div class="smaller">{{ gameStore.lastCheckpointSignature[2] }}</div>
          <div class="smaller">{{ gameStore.lastCheckpointSignature[3] }}</div>
        </div>
        <div class="flex column data_section">
          <div class="small turn">TURN: <span class="bold">{{ gameStore.currentState.turn }}</span></div>
          <div class="smaller turn">{{ gameStore.lastTurnSignature[0] }}</div>
          <div class="smaller turn">{{ gameStore.lastTurnSignature[1] }}</div>
        </div>
      </div>
    </div>
  </div>
</template>

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
  margin-top: 2px;
}
</style>
