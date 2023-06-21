<script setup>
import { RouterLink } from 'vue-router';
import { useStarknetStore } from '../stores/starknet';
const starknetStore = useStarknetStore();
</script>

<template>
    <div class="flex column flex-center max-height-without-navbar">
        <div id="MainMenu" class="flex column flex-center">
            <div class="logo">StarkPong</div>
            <div class="info">A fully P2P real-time, multiplayer game. Secured by StarkNet.</div>
            <div class="button">CREATE A GAME ROOM</div>
            <div class="button">JOIN A GAME ROOM</div>
            <RouterLink to="/faucet"><div class="button" v-if="starknetStore.isTestnet"><span class="bold">PONG</span> FAUCET</div></RouterLink>
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

.button {
    width: 450px;
    margin: 10px;
    color: white !important;
}

.bold {
    margin-right: 6px;
}

</style>