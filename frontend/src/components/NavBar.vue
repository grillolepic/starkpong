<script setup>
import { ref } from 'vue';
import { useRoute, RouterLink } from 'vue-router';
import { useStarknetStore } from '@/stores/starknet';
//import imgUrl from '../assets/img/pong_token.png';
import ConnectButton from './ConnectButton.vue';

//console.log(imgUrl);

const route = useRoute();
const starknetStore = useStarknetStore();

//import { useAlmanacStore } from '@/stores/almanac'
//const almanacStore = useAlmanacStore()

const menu = ref(false);
</script>

<template>
    <div id="Navbar" class="flex row">
        <router-link :to="'/'">
            <div id="Logo" class="logo">StarkPong</div>
        </router-link>
        <div class="flex row">
            <div id="pongTokenContainer" class="flex row flex-center">
                <div class="tokenImage containNoRepeatCenter"></div>
                <div class="tokenAmount">0.0 <span class="bold">PONG</span></div>
            </div>
            <ConnectButton class="fullscreen-connect-button" />
        </div>
    </div>
</template>

<style scoped>
#Navbar {
    z-index: 30;
    height: var(--navbar-height);
    margin-top: var(--navbar-top-margin );
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

#pongTokenContainer {
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
}

/*
#MenuButton {
    background-image: url('/img/menu.png');
    height: 40px;
    width: 40px;
    float: right;
    background-size: contain;
    background-repeat: no-repeat;
    background-position: center;
    margin: 10px;
    cursor: pointer;
}

#Menu {
    position: fixed;
    width: 300px;
    height: 100vh;
    right: 0px;
    top: 0px;
    background-color: rgb(21 16 50);
    transform: translateX(400px);
    transition: ease-in-out 0.5s;
    z-index: 9999;
    display: flex;
    flex-direction: column;
    flex-wrap: nowrap;
    justify-content: flex-start;
    align-content: flex-start;
    align-items: center;
    box-shadow: 0px 0px 20px #000000aa;
}

.fullscreen-connect-button {
    margin-top: 0.8rem;
    margin-right: 1rem;
    float: right;
}

.menu-connect-button {
    margin-top: 0.8rem;
}

.show-menu {
    transform: translateX(0px) !important;
}

#GreyBg {
    z-index: 500;
    background-color: rgba(0, 0, 0, 0);
    transition: ease-in-out 0.5s;
    position: fixed;
    top: 0px;
    left: 0px;
    width: 100vw;
    height: 100vh;
    pointer-events: none;
}

.show-menu-bg {
    pointer-events: all !important;
    background-color: rgba(0, 0, 0, 0.4) !important;
}

.selected {
    color: white !important;
}

.link {
    float: left;
    float: left;
    line-height: 70px;
    padding-left: 20px;
    color: white;
    font-size: 1.3em;
    padding-left: 1em;
    padding-right: 1em;
    text-align: center;
    font-size: 18px;
    font-family: 'Major Mono Display', monospace;
}

.in-menu {
    width: 300px;
}

.link:hover {
    color: rgb(190, 190, 190);
}

.in-menu-logo {
    width: 6em !important;
    height: 6em !important;
    margin-bottom: 1em;
}
*/
</style>