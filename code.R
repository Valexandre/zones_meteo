# Import des packages
library(tidyverse)
library(reshape2)
library(sf)
library(magick)
library(colorscale)

# Création des fonctions
sortunjpeg<-function(x,y,z,titre){
  jpeg(filename = paste0(titre,".jpg"), width=y, height = z, quality=100, units = "px",type="cairo")
  plot(x)
  dev.off()
}

`%!in%` = function(x,y) !(x %in% y)

# Création de la série d'images à partir d'une vidéo

system("ffmpeg -i METEO_ZONE/01012019.mp4 -r 5 -f image2 METEO_ZONE/img_01012019_%05d.png")
system("ffmpeg -i METEO_ZONE/02012019.mp4 -r 5 -f image2 METEO_ZONE/img_02012019_%05d.png")
system("ffmpeg -i METEO_ZONE/03012019.mp4 -r 5 -f image2 METEO_ZONE/img_03012019_%05d.png")
system("ffmpeg -i METEO_ZONE/11012019.mp4 -r 5 -f image2 METEO_ZONE/img_11012019_%05d.png")
system("ffmpeg -i METEO_ZONE/12012019.mp4 -r 5 -f image2 METEO_ZONE/img_12012019_%05d.png")
system("ffmpeg -i METEO_ZONE/13012019.mp4 -r 5 -f image2 METEO_ZONE/img_13012019_%05d.png")
system("ffmpeg -i METEO_ZONE/14012019.mp4 -r 5 -f image2 METEO_ZONE/img_14012019_%05d.png")

# A partir d'une image bien cadrée, on va créer le contour de la France en utilisant webplotdigitizer

# On charge les contours de la France
coords_france <- read_delim("METEO_ZONE/coords_france.csv", ";", escape_double = FALSE, trim_ws = TRUE)
coords_france<-coords_france%>%add_row(coords_france[1,])

France_sf<- sp::SpatialPolygons(list(sp::Polygons(list(sp::Polygon(cbind(coords_france$X,coords_france$Y))),ID="FRANCE")))%>%st_as_sf()

# Ensuite, on crée une grille hex à partir du polygone de la France et on ira ensuite voir quelle est la valeur moyenne de chaque image là dedans.

HexFrance<-France_sf%>%st_make_grid(cellsize = 10,square = F)%>%st_as_sf()
HexFrance<-HexFrance%>%mutate(ordre=row_number())
HexFrance<-st_intersection(HexFrance,France_sf)
HexFrance<-HexFrance[-1,]

# On crée ensuite une fonction pour passer d'une image plein écran à une carte divisée en hexagones

CreeDesHex<-function(arg){
  BonneImage1<-arg%>%image_read()%>%image_crop("370x315+160+20")
  DF<-BonneImage1[[1]]
  DF_df<-DF_df<- DF%>%
  as.integer %>% 
  melt() %>% 
  dcast(Var1+Var2~Var3, value.var="value")

  df1 <- as.data.frame(DF_df,wide="c") %>%     
  mutate(rgb.val=rgb(`1`/256,`2`/256,`3`/256))
  
  Jonction<-df1%>%
  st_as_sf(coords=c("Var2","Var1"))%>%
  st_join(HexFrance)
  
  Jonction<-Jonction%>%
  filter(!is.na(ordre))%>%
  st_drop_geometry()
  
  JonctionCouleur<-Jonction%>%
  group_by(ordre)%>%
  summarise(C1=round(median(`1`)),C2=round(median(`2`)),C3=round(median(`3`)))%>%ungroup()
  
  JonctionCouleur<-JonctionCouleur%>%
  mutate(rgb.val=rgb(C1/256,C2/256,C3/256))%>%
  left_join(HexFrance)%>%
  st_as_sf()%>%
  mutate(img=arg)
}


CalculeLesDistancesParZones<-function(datejourDDMMYYYY,referenceprevAM,debprevAM,finprevAM,
                                      referenceprevPM,debprevPM,finprevPM,
                                      referencetempAM,debtempAM,fintempAM,
                                      referencetempPM,debtempPM,fintempPM){
  
  ToutesLesImages<-list.files("METEO_ZONE/", full.names = TRUE, pattern = "\\.png$") 
  
  jour<-paste0("METEO_ZONE/img_",datejourDDMMYYYY)
  imagesaprendre <- ToutesLesImages[grepl(jour, ToutesLesImages)]
  ListesImages <- data.frame(
    img = imagesaprendre)
  ListesImages<-ListesImages%>%mutate(NumImage=parse_number(substr(img,54,80)))
  
  
  ImageASelectionner<-data.frame(
    EHAD=c(rep("matin",1+finprevAM-debprevAM), 
           rep("apresmidi",1+finprevPM-debprevPM), 
           rep("matin",1+fintempAM-debtempAM), 
           rep("apresmidi",1+fintempPM-debtempPM)), 
    rang=c(rep(1,(finprevAM-debprevAM)+(finprevPM-debprevPM)+2),
           rep(2,(fintempAM-debtempAM)+(fintempPM-debtempPM)+2)),
    NumImage=c(seq(from=debprevAM,to=finprevAM,by=1),
               seq(from=debprevPM,to=finprevPM,by=1),
               seq(from=debtempAM,to=fintempAM,by=1),
               seq(from=debtempPM,to=fintempPM,by=1)))
  
  #On ne garde que les images qui sont comprises dans les intervalles de EnsembleDebutEtFin
  CalculsCouleursMoy<-ListesImages%>%
    filter(NumImage %in%ImageASelectionner$NumImage)%>%
    left_join(ImageASelectionner)%>%
    mutate(Ordre=paste0(EHAD,"_",rang))
  
  CartesJourneeEnCours<-CalculsCouleursMoy$img%>%
    map_dfr(CreeDesHex)
    
  saveRDS(CartesJourneeEnCours,paste0("CartesJourneeEnCours_",datejourDDMMYYYY,".Rdata"))
  
  References<-tibble(
    img=c(paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",referenceprevAM,".png"),
          paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",referenceprevPM,".png"),
          paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",referencetempAM,".png"),
          paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",referencetempPM,".png")),
    Ordre=c("matin_1","apresmidi_1","matin_2","apresmidi_2"))
  
  CouleursdesHexRef<-CartesJourneeEnCours%>%filter(img%in%References$img)%>%ungroup()
  
  CouleursdesHexRef<-CouleursdesHexRef%>%ungroup()%>%st_drop_geometry()%>%
    left_join(References%>%ungroup()%>%select(img,Ordre))%>%
    select(ordre,rgb.val,Ordre)%>%rename(coulref=2)
  
  CouleursDesHexAvecCouleurRef<-CartesJourneeEnCours%>%st_drop_geometry()%>%
    select(ordre,rgb.val,img)%>%ungroup()%>%
    left_join(CalculsCouleursMoy%>%select(img,Ordre),by=c("img"="img"))%>%
    left_join(CouleursdesHexRef,by=c("Ordre"="Ordre","ordre"="ordre"))%>%
    mutate(DistanceCouleur=colorscale::chroma_distance(coulref, rgb.val,"rgb"))
  
  MoyenneDesDistances<-CouleursDesHexAvecCouleurRef%>%
    group_by(ordre)%>%
    summarise(DistMoy=mean(DistanceCouleur))%>%
    left_join(HexFrance)%>%st_as_sf()
  
  sortunjpeg(MoyenneDesDistances%>%ggplot()+
               geom_sf(aes(fill=DistMoy),colour="white"),800,800,paste0("moyDist",datejourDDMMYYYY))
  
  
  MoyenneDesDistances2<-CouleursDesHexAvecCouleurRef%>%
    group_by(ordre,Ordre)%>%
    summarise(DistMoy=mean(DistanceCouleur))%>%
    left_join(HexFrance)%>%st_as_sf()
  
  sortunjpeg(MoyenneDesDistances2%>%ggplot()+
               geom_sf(aes(fill=DistMoy),colour="white")+facet_wrap(Ordre~.),800,800,paste0("moyDist",datejourDDMMYYYY,"_2"))
  
  saveRDS(CouleursDesHexAvecCouleurRef,paste0("DonneesPourmoyDist",datejourDDMMYYYY,".Rdata"))
  
  sortunjpeg(image_append(c(
    image_append(c(
    paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",referenceprevAM,".png")%>%image_read(),
    paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",debprevAM,".png")%>%image_read(),
    paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",finprevAM,".png")%>%image_read())),
    image_append(c(
      paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",referenceprevPM,".png")%>%image_read(),
      paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",debprevPM,".png")%>%image_read(),
      paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",finprevPM,".png")%>%image_read())),
    image_append(c(
        paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",referencetempAM,".png")%>%image_read(),
        paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",debtempAM,".png")%>%image_read(),
        paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",fintempAM,".png")%>%image_read())),
    image_append(c(
      paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",referencetempPM,".png")%>%image_read(),
      paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",debtempPM,".png")%>%image_read(),
      paste0("METEO_ZONE/img_",datejourDDMMYYYY,"_00",fintempPM,".png")%>%image_read()))),stack=TRUE),
    1200,1200,paste0("montageimagesbases_",datejourDDMMYYYY))
  
}

#Exemple pour le 2 janvier
CalculeLesDistancesParZones(datejourDDMMYYYY = "02012019",
                            referenceprevAM = 196,debprevAM = 196,finprevAM = 241,
                            referenceprevPM = 252,debprevPM = 246,finprevPM = 300,
                            referencetempAM = 310,debtempAM = 308,fintempAM = 338,
                            referencetempPM = 412,debtempPM = 412,fintempPM = 451)
