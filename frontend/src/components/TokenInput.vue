<script setup>
import { ref } from 'vue';
import { useGameTokenStore } from '../stores/game_token';

const gameTokenStore = useGameTokenStore();
const tokenAmount = ref('0');

function useMax() {
    tokenAmount.value = parseFloat(gameTokenStore.balanceAsFloat).toString()
}

function onChange() {
    if (tokenAmount.value == "") {
        tokenAmount.value = 0;
    }
    tokenAmount.value = parseFloat(tokenAmount.value).toString();
}

function onInput() {
    if (typeof tokenAmount.value == "string") {
        var rgx = /^[0-9]*\.?[0-9]*$/;
        let new_value = tokenAmount.value.match(rgx);
        tokenAmount.value = new_value;
    }
}

defineExpose({ tokenAmount });
</script>

<template>
    <div id="TokenInputContainer" class="flex row flex-center">
        <div class="label">Wager:</div>
        <div id="tokenInput" class="flex row flex-center">
            <input v-model="tokenAmount" @change="onChange" @input="onInput">
            <div class="max" @click="useMax()">USE MAX</div>
        </div>
        <div class="tokenName bold">{{ gameTokenStore.tokenName }}</div>
    </div>
</template>

<style scoped>
#TokenInputContainer {
    width: 450px;
}

.label {
    margin-right: 10px;
    font-size: 18px;
}

.max {
    font-size: 12px;
    cursor: pointer;
}

.tokenName {
    margin-left: 10px;
}

#tokenInput {
    min-width: 345px;
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
    width: 250px;
    background-color: transparent;
    border: none;
    color: var(--white);
    font-size: 18px;
    letter-spacing: 2px;
    outline: none;
}

input::-webkit-outer-spin-button,
input::-webkit-inner-spin-button {
    -webkit-appearance: none;
    margin: 0;
}

input[type=number] {
    -moz-appearance: textfield;
}
</style>