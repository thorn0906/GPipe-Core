{-# LANGUAGE TypeFamilies, FlexibleContexts, GADTs, TypeSynonymInstances, ScopedTypeVariables, FlexibleInstances, GeneralizedNewtypeDeriving #-}

module Graphics.GPipe.Uniform where

import Graphics.GPipe.Buffer 
import Graphics.GPipe.Frame
import Graphics.GPipe.FrameCompiler
import Graphics.GPipe.Shader
import Control.Arrow
import Control.Monad.Trans.Writer
import Control.Monad.Trans.Reader
import Control.Monad.Trans.Class (lift)
import Control.Category hiding ((.))
import qualified Data.IntMap as Map
import Data.IntMap.Lazy (insert)


class BufferFormat (UniformBufferFormat a) => Uniform a where
    type UniformBufferFormat a
    toUniform :: ToUniform (UniformBufferFormat a) a 

type UniformHostFormat x = HostFormat (UniformBufferFormat x)

-- uniformBlock ::  forall os f b. Uniform b => Frame os f (UniformHostFormat b, Proxy b) b
 
toUniformBlock :: forall os f s b. Uniform b => (s -> (Buffer os (BUniform (UniformBufferFormat b)), Int)) -> Frame os f s b
toUniformBlock sf = Frame $ do 
                   blockId <- getName
                   let (u, offToStype) = shaderGen (useUniform (buildUDecl offToStype) blockId)
                   doForUniform blockId $ \s bind -> let (ub, i) = sf s 
                                                     in  glBindBufferRange glUNIFORM_ARRAY bind (bufName ub) (i * bufElementSize ub) (bufElementSize ub)
                   return u
    where
            sampleBuffer = makeBuffer undefined undefined :: Buffer os (BUniform (UniformBufferFormat b))
            ToUniform (Kleisli shaderGenF) = toUniform :: ToUniform (UniformBufferFormat b) b
            fromBUnifom (BUniform b) = b
            shaderGen :: (Int -> ShaderM String) -> (b, OffsetToSType) -- Int is name of uniform block
            shaderGen = runReader $ runWriterT $ shaderGenF $ fromBUnifom $ bufBElement sampleBuffer $ BInput 0 0

            doForUniform :: Int -> (s -> Binding -> IO()) -> FrameM s ()
            doForUniform n io = modifyRenderIO (\s -> s { uniformNameToRenderIO = insert n io (uniformNameToRenderIO s) } )

buildUDecl :: OffsetToSType -> ShaderGlobDeclM ()
buildUDecl = buildUDecl' 0 . Map.assocs 
    where buildUDecl' p ((off, stype):xs) | off == p = do tellGlobal $ stypeName stype
                                                          tellGlobal " u"
                                                          tellGlobalLn $ show off
                                                          buildUDecl' (p + stypeSize stype) xs
                                          | off > p = do tellGlobal " float pad"
                                                         tellGlobalLn $ show p
                                                         buildUDecl' (p + 4) xs
                                          | otherwise = error "buildUDecl: Expected all sizes to be multiple of 4"
          buildUDecl' _ [] = return ()

type OffsetToSType = Map.IntMap SType  

glUniformBlockBinding :: Int -> Int -> Int -> IO ()
glUniformBlockBinding a b c = putStrLn $ "glUniformBlockBinding " ++ show (a,b,c)

glBindBufferRange :: Int -> Int -> Int -> Int -> Int -> IO ()
glBindBufferRange a b c d e = putStrLn $ "glBindBufferRange " ++ show (a,b,c,d,e)                            

glUNIFORM_ARRAY = 0

newtype ToUniform a b = ToUniform (Kleisli (WriterT OffsetToSType (Reader (Int -> ShaderM String))) a b) deriving (Category, Arrow) 

instance Uniform (S x Float) where
    type UniformBufferFormat (S x Float) = BFloat
    toUniform = ToUniform $ Kleisli $ \bIn -> do let offset = bOffset bIn
                                                 tell $ Map.singleton offset STypeFloat
                                                 useF <- lift ask
                                                 return $ S $ useF offset  
