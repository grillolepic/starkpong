<script setup>
import { ref, onMounted } from 'vue';
import { RouterLink, useRouter } from 'vue-router';
import { useStarknetStore } from '../stores/starknet';
import { useGameTokenStore } from '../stores/game_token';
import TransactionStatus from '../components/TransactionStatus.vue';
import TokenInput from '../components/TokenInput.vue';

const starknetStore = useStarknetStore();
const gameTokenStore = useGameTokenStore();
const router = useRouter();

let game_room_contract = ref("");

onMounted(async () => {
    //router.push('/');
});

function onInput() {

}
</script>

<template>
    <div class="flex column flex-center max-height-without-navbar">
        <div id="MainMenu" class="flex column flex-center">
            <div class="logo">Join Room</div>
            <div id="createRoomContents" class="flex column flex-center" v-if="starknetStore.transaction.status == null">
                <div id="ContractInputContainer" class="flex row flex-center">
                    <div class="label bold">Address:</div>
                    <div id="contractInput" class="flex row flex-center">
                        <input type="text" v-model="game_room_contract" @input="onInput" />
                    </div>
                </div>
                <div class="button" @click="gameTokenStore.claim()" v-if="starknetStore.transaction.status == null">
                    JOIN GAME ROOM</div>
                <RouterLink to="/" v-if="starknetStore.transaction.status == null">
                    <div class="info backToHome">Back to Home</div>
                </RouterLink>
            </div>
            <TransactionStatus v-else />
        </div>
    </div>
</template>

<style scoped>
#createRoomContents {
    justify-content: flex-start;
    height: 200px;
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

.info {
    margin-top: 15px;
    text-align: center;
}

.backToHome {
    color: white !important;
    text-decoration: underline;
}

.button {
    margin-top: 25px;
    width: 450px;
}

.inline-spinner {
    margin-top: 25px;
}

#ContractInputContainer {
    margin-top: 25px;
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
    width: 200px;
    background-color: transparent;
    border: none;
    color: var(--white);
    font-size: 18px;
    letter-spacing: 2px;
    outline: none;
}
</style>