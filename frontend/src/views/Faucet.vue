<script setup>
import { onMounted } from 'vue';
import { RouterLink, useRouter } from 'vue-router';
import { useStarknetStore } from '../stores/starknet';
import { useGameTokenStore } from '../stores/game_token';
import TransactionStatus from '../components/TransactionStatus.vue';

const starknetStore = useStarknetStore();
const gameTokenStore = useGameTokenStore();
const router = useRouter();

onMounted(() => {
    if (!starknetStore.isTestnet) {
        router.push('/');
    }
});
</script>

<template>
    <div class="flex column flex-center max-height-without-navbar">
        <div id="MainMenu" class="flex column flex-center">
            <div class="logo">Faucet</div>
            <div id="faucetContents" class="flex column flex-center" v-if="starknetStore.transaction.status == null">
                <div v-if="gameTokenStore.loadingFaucetStatus" class="flex column flex-center">
                    <div class="inline-spinner"></div>
                </div>
                <div v-else-if="gameTokenStore.faucetReady" class="flex column flex-center">
                    <div class="button big-button" @click="gameTokenStore.claim()"
                        v-if="starknetStore.transaction.status == null">GET
                        500 PONG TOKENS</div>
                    <RouterLink to="/" v-if="starknetStore.transaction.status == null">
                        <div class="button big-button">BACK TO HOME</div>
                    </RouterLink>
                </div>
                <div v-else class="flex column flex-center">
                    <div class="info red-text">You have already claimed <spanc class="bold">PONG</spanc>tokens on the last
                        24hs. You will be able to claim more tokens on {{ gameTokenStore.nextClaim }} </div>
                    <RouterLink to="/" v-if="starknetStore.transaction.status == null">
                        <div class="button big-button">BACK TO HOME</div>
                    </RouterLink>
                </div>
            </div>
            <TransactionStatus v-else />
        </div>
    </div>
</template>

<style scoped>
.logo {
    font-size: 65px;
    line-height: 65px;
}

.info {
    margin: 15px 0px;
    text-align: center;
}

.bold {
    margin-right: 6px;
}

#faucetContents {
    justify-content: flex-start;
    height: 250px;
    width: 450px;
}

.inline-spinner {
    margin-top: 25px;
}
</style>