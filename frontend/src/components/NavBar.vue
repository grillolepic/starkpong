<script setup>
import { ref } from 'vue';
import { useRoute, RouterLink } from 'vue-router';
import { useStarknetStore } from '@/stores/starknet';
import { useGameTokenStore } from '../stores/game_token';
import ConnectButton from './ConnectButton.vue';

const route = useRoute();
const starknetStore = useStarknetStore();
const gameTokenStore = useGameTokenStore();

const menu = ref(false);
</script>

<template>
    <div id="Navbar" class="flex row">
        <router-link :to="'/'">
            <div id="Logo" class="logo">StarkPong</div>
        </router-link>
        <div class="flex row">
            <div id="gameTokenContainer" class="flex row flex-center" v-if="starknetStore.networkOk">
                <div class="tokenImage containNoRepeatCenter noSelect"></div>
                <div class="tokenAmount noSelect" v-if="!gameTokenStore.loadingBalance">
                    {{ gameTokenStore.balanceForDisplay }}
                    <span class="bold">{{ gameTokenStore.tokenName }}</span>
                </div>
                <div v-else class="tokenAmount">
                    <div class="inline-spinner"></div>
                </div>
            </div>
            <ConnectButton class="fullscreen-connect-button" />
        </div>
    </div>
</template>

<style scoped>
#Navbar {
    z-index: 30;
    height: var(--navbar-height);
    margin-top: var(--navbar-top-margin);
    width: 98%;
    justify-content: space-between;
    align-items: center;
}

#Logo {
    float: left;
    color: var(--white);
    font-size: 33px;
    transition: ease 0.1s;
}

#Logo:hover {
    transform: scale(1.05);
}

#gameTokenContainer {
    padding: 5px 20px;
    height: 40px;
    border-radius: 0.375rem;
    background-color: var(--grey-base);
    margin-right: 25px;
}

.tokenImage {
    width: 25px;
    height: 25px;
    border: 1px solid var(--white-mute);
    border-radius: 100%;
    background-image: url(/src/assets/img/pong_token.png);
    margin-right: 10px;
}

.tokenAmount {
    color: var(--white);
    text-align: center;
}

</style>