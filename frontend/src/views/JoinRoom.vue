<script setup>
import { ref, onMounted } from 'vue';
import { RouterLink, useRoute } from 'vue-router';
import { useStarknetStore } from '../stores/starknet';
import { useGameTokenStore } from '../stores/game_token';
import { useGameRoomFactoryStore } from '../stores/game_room_factory';
import TransactionStatus from '../components/TransactionStatus.vue';
import TokenInput from '../components/TokenInput.vue';
import { formatEther } from '../helpers/ethereumHelpers';

const starknetStore = useStarknetStore();
const gameTokenStore = useGameTokenStore();
const gameRoomFactoryStore = useGameRoomFactoryStore();

let game_room_contract = ref("");

onMounted(() => {
    gameRoomFactoryStore.updateGameRoom();
    const route = useRoute();
    if ("room" in route.query) {
        game_room_contract.value = route.query.room;
        setTimeout(() => {
            gameRoomFactoryStore.updateGameRoomToJoin(game_room_contract.value, true);
        }, 2000);
    } else {
        gameRoomFactoryStore.resetGameRoomToJoin();
    }
});

function onInput() {
    gameRoomFactoryStore.updateGameRoomToJoin(game_room_contract.value, false);
}
</script>

<template>
    <div class="flex column flex-center max-height-without-navbar">
        <div id="MainMenu" class="flex column flex-center">
            <div class="logo">Join Room</div>
            <div id="createRoomContents" class="flex column flex-center"
                v-if="starknetStore.transaction.status == null && !gameRoomFactoryStore.loadingGameRoom">
                <div id="ContractInputContainer" class="flex row flex-center">
                    <div class="label">Address:</div>
                    <div id="contractInput" class="flex row flex-center">
                        <input type="text" v-model="game_room_contract" @input="onInput" />
                    </div>
                </div>
                <div v-if="gameRoomFactoryStore.gameRoomToJoin.checking" class="flex column flex-center gameInfoSection">
                    <div class="inline-spinner"></div>
                </div>
                <div v-else-if="gameRoomFactoryStore.gameRoomToJoin.error == null && gameRoomFactoryStore.gameRoomToJoin.wager != null"
                    class="flex column flex-center gameInfoSection">
                    <div class="flex row flex-center">
                        <div class="label">Required bet:</div>
                        <div class="info">{{ parseFloat(formatEther(gameRoomFactoryStore.gameRoomToJoin.wager)) }} <span
                                class="bold">{{
                                    gameTokenStore.tokenName }}</span></div>
                    </div>
                </div>
                <div v-else-if="gameRoomFactoryStore.gameRoomToJoin.error != null" class="flex column flex-center gameInfoSection">
                    <div class="info bold red">{{ gameRoomFactoryStore.gameRoomToJoin.error }}</div>
                </div>
                <div class="button big-button" @click="gameRoomFactoryStore.joinRoom()"
                    v-if="starknetStore.transaction.status == null && !gameRoomFactoryStore.gameRoomToJoin.checking && gameRoomFactoryStore.gameRoomToJoin.error == null">
                    JOIN GAME ROOM</div>
                <RouterLink to="/" v-if="starknetStore.transaction.status == null">
                    <div class="button big-button">BACK TO HOME</div>
                </RouterLink>
            </div>
            <div v-else-if="gameRoomFactoryStore.loadingGameRoom" class="inline-spinner"></div>
            <TransactionStatus v-else />
        </div>
    </div>
</template>

<style scoped>
#createRoomContents {
    justify-content: flex-start;
    width: 450px;
}

.label {
    margin-right: 10px;
    font-size: 18px;
}

.logo {
    font-size: 65px;
    line-height: 65px;
}

.backToHome {
    color: white !important;
    text-decoration: underline;
}


#ContractInputContainer {
    margin: 15px 0px;
}

.gameInfoSection {
    margin-top: 10px;
    min-height: 50px;
    justify-content: flex-start;
}

#contractInput {
    min-width: 360px;
    padding: 5px 10px;
    height: 40px;
    border-radius: 0.375rem;
    background-color: var(--grey-base);
    border: 1px solid white;
    letter-spacing: 2px;
    color: var(--white);
    font-size: 18px;
    justify-content: space-between;
}

input {
    width: 100%;
    background-color: transparent;
    border: none;
    color: var(--white);
    font-size: 18px;
    letter-spacing: 1px;
    outline: none;
}
</style>