<script setup>
import { RouterLink } from 'vue-router';
import { useStarknetStore } from '../stores/starknet';
import { useGameRoomStore } from '../stores/game_room';

const starknetStore = useStarknetStore();
const gameRoomStore = useGameRoomStore();
</script>

<template>
    <div class="flex column flex-center max-height-without-navbar">
        <div id="MainMenu" class="flex column flex-center">
            <div class="logo">StarkPong</div>
            <div class="info">A fully P2P real-time, multiplayer game. Secured by StarkNet.</div>
            <div v-if="gameRoomStore.currentGameRoom != null" class="flex column section">
                <RouterLink :to="{ name: 'GameRoom', params: { id: gameRoomStore.currentGameRoom }}"><div class="button big-button">CONTINUE GAME</div></RouterLink>
            </div>
            <div v-else class="flex column section">
                <RouterLink to="/create"><div class="button big-button">CREATE A GAME ROOM</div></RouterLink>
                <RouterLink to="/join"><div class="button big-button">JOIN A GAME ROOM</div></RouterLink>
                <RouterLink to="/faucet"><div class="button big-button" v-if="starknetStore.isTestnet"><span class="bold">PONG</span> FAUCET</div></RouterLink>
            </div>
        </div>
    </div>
</template>

<style scoped>
.logo {
  font-size: 65px;
  line-height: 65px;
}

.info {
    margin-bottom: 15px;
}

.bold {
    margin-right: 6px;
}
</style>