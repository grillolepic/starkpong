<script setup>
import { useStarknetStore } from '@/stores/starknet';

const starknetStore = useStarknetStore();

function goToTransactionLink() {
    if (starknetStore.transaction.link != null) {
        window.open(starknetStore.transaction.link, '_blank');
    }
}
</script>

<template>
    <div id="TransactionStatus" class="flex row flex-center" v-if="starknetStore.transaction.status != null">
        <div v-if="starknetStore.transaction.status == 0" class="flex column section">
            <div class="inline-spinner"></div>
        </div>
        <div v-if="starknetStore.transaction.status == 1" class="flex column">
            <div class="info big">Waiting for transaction...</div>
            <div class="info goBack" @click="goToTransactionLink()">View on StarkScan</div>
        </div>
        <div v-if="starknetStore.transaction.status == 2" class="flex column">
            <div class="info bold big">Transaction Complete!</div>
            <div class="info goBack" @click="goToTransactionLink()">View on StarkScan</div>
            <div class="info goBack" @click="starknetStore.resetTransaction()">Go back</div>
        </div>
        <div v-if="starknetStore.transaction.status == -1" class="flex column">
            <div class="info red big"><span class="bold">ERROR: </span>{{ starknetStore.transaction.error }}</div>
            <div class="info goBack" @click="starknetStore.resetTransaction()">Go back</div>
        </div>
    </div>
</template>

<style scoped>
#TransactionStatus {
    align-items: flex-start;
    height: 250px;
}

.section {
    align-items: flex-start;
}

.inline-spinner {
    margin-top: 25px;
}

.info {
    margin-top: 15px;
    text-align: center;
}

.goBack {
    cursor: pointer;
    color: white !important;
    text-decoration: underline;
}

.big {
    font-size: 21px;
}
</style>