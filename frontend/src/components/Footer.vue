<script setup>
import { useGameRoomFactoryStore } from '../stores/game_room_factory';

const gameRoomFactoryStore = useGameRoomFactoryStore();

function goToGithub() {
    window.open('https://github.com/grillolepic/pragma_cairo1_hackathon', '_blank');
}

function goToTwitter() {
    window.open('https://twitter.com/grillo_eth', '_blank');
}
</script>

<template>
    <div id="Footer" class="flex row flex-center">
        <div class="noSelect smallText">
            <span v-if="gameRoomFactoryStore.gamesPlayed != null">
                <span class="bold">{{ gameRoomFactoryStore.gamesPlayed.toString() }}</span> GAME ROOMS CREATED
            </span>
        </div>
        <div class="flex row">
            <div class="flex row flex-center" @click="goToTwitter()">
                <div class="footer-logo containNoRepeatCenter twitter"></div>
            </div>
            <div class="flex row flex-center" @click="goToGithub()">
                <div class="footer-logo containNoRepeatCenter github"></div>
            </div>
        </div>
    </div>
</template>

<style scoped>
#Footer {
    z-index: 30;
    height: var(--footer-height);
    margin-bottom: var(--footer-bottom-margin);
    width: 98%;
    justify-content: space-between;
}

.footer-logo {
    width: 25px;
    height: 25px;
    cursor: pointer;
    transition: ease 0.1s;
}

.footer-logo:hover {
    transform: scale(1.05);
}

.twitter {
    background-image: url(/src/assets/img/twitter.png);
    margin-right: 15px;
}

.github {
    background-image: url(/src/assets/img/github.png);
}

.smallText {
    font-size: 12px;
    margin-left: 10px;
}
</style>